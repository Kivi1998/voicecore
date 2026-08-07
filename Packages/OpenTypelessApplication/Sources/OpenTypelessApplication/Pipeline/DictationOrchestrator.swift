import Foundation
import OpenTypelessDomain

/// 口述会话编排器：唯一推进口述状态机的模块。
///
/// 职责（`docs/ARCHITECTURE.md` §4.2）：
/// 1. 开始录音前创建数据库记录和录音目标文件；
/// 2. 音频持续写盘（由 AudioCapture/AudioFileStore 保证）；
/// 3. 停止后：关闭校验文件 → 语音识别 → 保存原始转录 → 可选改写
///    → 保存最终文字 → 自动输入；
/// 4. 每一步均持久化状态、错误类别和时间，尝试记录完整写回；
/// 5. 同一时刻最多一个活跃录音会话；
/// 6. 自动输入失败不回滚转录结果。
public actor DictationOrchestrator {
    private let records: any DictationRecordRepository
    private let audioFiles: any AudioFileStore
    private let audioCapture: any AudioCapture
    private let providerFactory: any ProviderFactory
    private let optionsProvider: any PipelineOptionsProvider
    private let clipboard: any ClipboardService
    private let injector: any TextInjector
    private let audioURLResolver: @Sendable (String) throws -> URL
    private let now: @Sendable () -> Date

    /// 当前活跃会话记录标识（录音中或处理中）。
    public private(set) var activeRecordID: UUID?

    private let eventStream: AsyncStream<DictationSessionEvent>
    private var eventContinuation: AsyncStream<DictationSessionEvent>.Continuation?

    /// 会话事件流；界面据此更新录音胶囊与状态。
    public nonisolated var events: AsyncStream<DictationSessionEvent> {
        eventStream
    }

    public init(
        records: any DictationRecordRepository,
        audioFiles: any AudioFileStore,
        audioCapture: any AudioCapture,
        providerFactory: any ProviderFactory,
        optionsProvider: any PipelineOptionsProvider,
        clipboard: any ClipboardService,
        injector: any TextInjector,
        audioURLResolver: @escaping @Sendable (String) throws -> URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.records = records
        self.audioFiles = audioFiles
        self.audioCapture = audioCapture
        self.providerFactory = providerFactory
        self.optionsProvider = optionsProvider
        self.clipboard = clipboard
        self.injector = injector
        self.audioURLResolver = audioURLResolver
        self.now = now
        var continuation: AsyncStream<DictationSessionEvent>.Continuation!
        eventStream = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    // MARK: - 录音控制

    /// 按一次快捷键：开始录音。
    ///
    /// 先建库记录与目标文件再开始采集；已有活跃会话时明确拒绝。
    /// - Returns: 新记录标识。
    @discardableResult
    public func startRecording() async throws -> UUID {
        guard activeRecordID == nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "已有录音进行中",
                isRetryable: false
            )
        }
        guard let (_, snapshot) = try await providerFactory.makeSpeechProvider() else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "尚未配置语音识别模型，请先前往设置完成配置",
                isRetryable: false
            )
        }

        let startedAt = now()
        let recordID = UUID()
        let relativePath = try audioFiles.prepareDestination(
            recordID: recordID,
            startedAt: startedAt,
            fileExtension: "m4a"
        )
        let record = DictationRecord(
            id: recordID,
            status: .created,
            startedAt: startedAt,
            audioRelativePath: relativePath,
            audioMimeType: "audio/mp4",
            speechSnapshot: snapshot,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        try await records.create(record)

        do {
            try await audioCapture.start(deviceID: nil, writingTo: relativePath)
        } catch let error as DictationError {
            try? await transition(recordID: recordID, to: .recordingFailed, error: error)
            emit(.sessionFinished(recordID: recordID, status: .recordingFailed))
            throw error
        }
        try await transition(recordID: recordID, to: .recording)
        activeRecordID = recordID
        return recordID
    }

    /// 再按一次快捷键：结束录音并异步执行转录→改写→输入流水线。
    public func stopRecording() async {
        guard let recordID = activeRecordID else { return }
        Task {
            await runPipeline(recordID: recordID)
        }
    }

    /// Esc 取消当前录音：安全关闭文件，记录标记取消（录音保留）。
    public func cancelRecording() async {
        guard let recordID = activeRecordID else { return }
        await audioCapture.cancel()
        activeRecordID = nil
        try? await transition(recordID: recordID, to: .cancelled)
        emit(.sessionFinished(recordID: recordID, status: .cancelled))
    }

    // MARK: - 主流水线

    private func runPipeline(recordID: UUID) async {
        defer { activeRecordID = nil }
        do {
            guard var record = try await records.get(id: recordID) else { return }
            let options = try await optionsProvider.currentOptions()

            // 1. 关闭并校验录音文件。
            let captureResult = try await audioCapture.stop()
            let fileInfo = try audioFiles.finalize(relativePath: captureResult.relativePath)
            record.stoppedAt = now()
            record.durationMs = captureResult.durationMs
            record.audioSizeBytes = fileInfo.sizeBytes
            record.updatedAt = now()
            try await records.save(record)
            try await transition(recordID: recordID, to: .audioSaved)

            // 2. 语音识别（失败状态在 performTranscription 内落库）。
            let rawText = try await performTranscription(recordID: recordID)

            // 3. 可选改写；关闭改写时原始转录直接成为最终文字。
            let rewritePair = options.rewriteEnabled
                ? try await providerFactory.makeRewriteProvider()
                : nil
            if let (rewriteProvider, rewriteSnapshot) = rewritePair {
                var updating = try await requireRecord(recordID)
                updating.rewriteSnapshot = rewriteSnapshot
                updating.rewriteProfileID = rewriteSnapshot.profileID
                updating.updatedAt = now()
                try await records.save(updating)
                do {
                    let finalText = try await performRewrite(
                        recordID: recordID,
                        originalText: rawText,
                        provider: rewriteProvider
                    )
                    try await saveFinalText(recordID: recordID, finalText: finalText)
                    try await transition(recordID: recordID, to: .ready)
                } catch let error as DictationError {
                    // 改写失败保留原始文字，可仅重新改写。
                    try? await transition(recordID: recordID, to: .rewriteFailed, error: error)
                    emit(.sessionFinished(recordID: recordID, status: .rewriteFailed))
                    return
                }
            } else {
                try await saveFinalText(recordID: recordID, finalText: rawText)
                try await transition(recordID: recordID, to: .ready)
            }

            // 4. 自动输入；失败不回滚转录结果。
            try await deliver(recordID: recordID, options: options)
        } catch is CancellationError {
            await emitTerminal(recordID: recordID)
        } catch {
            // 录音/文件阶段的兜底；后续阶段的失败已在各阶段落库。
            await failRecordingStage(recordID: recordID, error: error)
            await emitTerminal(recordID: recordID)
        }
    }

    /// 转录阶段（含尝试记录写回）；成功返回原始文字。
    private func performTranscription(recordID: UUID) async throws -> String {
        guard let (provider, _) = try await providerFactory.makeSpeechProvider() else {
            let error = DictationError(
                category: .configurationInvalid,
                userMessage: "语音识别模型配置已被移除，请重新配置",
                isRetryable: false
            )
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: error)
            throw error
        }
        guard let record = try await records.get(id: recordID),
              let relativePath = record.audioRelativePath,
              (try? audioFiles.info(relativePath: relativePath).exists) == true
        else {
            let error = DictationError(
                category: .audioInvalid,
                userMessage: "录音文件缺失",
                isRetryable: false
            )
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: error)
            throw error
        }

        let options = await (try? optionsProvider.currentOptions()) ?? PipelineOptions()
        var attempt = try await RecordAttempt(
            id: UUID(),
            recordID: recordID,
            stage: .transcription,
            attemptNumber: (records.attemptCount(recordID: recordID, stage: .transcription)) + 1,
            providerKind: record.speechSnapshot.protocolKind,
            modelName: record.speechSnapshot.modelName,
            startedAt: now()
        )
        try await records.addAttempt(attempt)
        try await transition(recordID: recordID, to: .transcribing)

        do {
            let vocabulary = await (try? providerFactory.vocabularyTerms()) ?? []
            // 长音频允许更长总超时：基础 60 秒 + 每 2 秒音频增加 1 秒，封顶 600。
            let timeout = min(600, 60 + TimeInterval(record.durationMs) / 1000 / 2)
            let result = try await provider.transcribe(SpeechRequest(
                audioFile: audioURLResolver(relativePath),
                mimeType: record.audioMimeType ?? "audio/mp4",
                durationMs: record.durationMs,
                languageHint: options.languageHint,
                vocabularyTerms: vocabulary,
                timeoutSeconds: timeout,
                recordID: recordID,
                attemptID: attempt.id
            ))
            attempt.success = true
            attempt.finishedAt = now()
            attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
            attempt.providerRequestID = result.providerRequestID
            try await records.saveAttempt(attempt)

            var updated = record
            updated.rawTranscript = result.text
            updated.detectedLanguage = result.detectedLanguage
            updated.updatedAt = now()
            try await records.save(updated)
            try await transition(recordID: recordID, to: .transcribed)
            return result.text
        } catch let error as DictationError {
            attempt.success = false
            attempt.finishedAt = now()
            attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
            attempt.errorCategory = error.category
            attempt.errorMessage = error.userMessage
            try? await records.saveAttempt(attempt)
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: error)
            throw error
        } catch is CancellationError {
            let error = DictationError(category: .unknown, userMessage: "转录已取消", isRetryable: false)
            attempt.success = false
            attempt.finishedAt = now()
            attempt.errorCategory = error.category
            attempt.errorMessage = error.userMessage
            try? await records.saveAttempt(attempt)
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: error)
            throw CancellationError()
        } catch {
            let mapped = DictationError(category: .unknown, userMessage: "转录发生未知错误")
            attempt.success = false
            attempt.finishedAt = now()
            attempt.errorCategory = mapped.category
            attempt.errorMessage = mapped.userMessage
            try? await records.saveAttempt(attempt)
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: mapped)
            throw mapped
        }
    }

    /// 改写阶段（含尝试记录写回）；成功返回最终文字。
    private func performRewrite(
        recordID: UUID,
        originalText: String,
        provider: any RewriteProvider
    ) async throws -> String {
        let snapshot = try await records.get(id: recordID)?.rewriteSnapshot
        var attempt = try await RecordAttempt(
            id: UUID(),
            recordID: recordID,
            stage: .rewrite,
            attemptNumber: (records.attemptCount(recordID: recordID, stage: .rewrite)) + 1,
            providerKind: snapshot?.protocolKind,
            modelName: snapshot?.modelName,
            startedAt: now()
        )
        try await records.addAttempt(attempt)
        try await transition(recordID: recordID, to: .rewriting)

        do {
            let vocabulary = await (try? providerFactory.vocabularyTerms()) ?? []
            let result = try await provider.rewrite(RewriteRequest(
                originalText: originalText,
                vocabularyTerms: vocabulary,
                recordID: recordID,
                attemptID: attempt.id
            ))
            attempt.success = true
            attempt.finishedAt = now()
            attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
            attempt.providerRequestID = result.providerRequestID
            try await records.saveAttempt(attempt)
            return result.finalText
        } catch let error as DictationError {
            attempt.success = false
            attempt.finishedAt = now()
            attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
            attempt.errorCategory = error.category
            attempt.errorMessage = error.userMessage
            try? await records.saveAttempt(attempt)
            throw error
        } catch {
            let mapped = DictationError(category: .unknown, userMessage: "改写发生未知错误")
            attempt.success = false
            attempt.finishedAt = now()
            attempt.errorCategory = mapped.category
            attempt.errorMessage = mapped.userMessage
            try? await records.saveAttempt(attempt)
            throw mapped
        }
    }

    /// 自动输入与剪贴板恢复编排；输入失败不丢文本。
    private func deliver(recordID: UUID, options: PipelineOptions) async throws {
        guard let record = try await records.get(id: recordID),
              let finalText = record.finalText else { return }

        guard options.autoInsert else {
            // 关闭自动输入：最终文字已保存，流程直接完成。
            var updated = record
            updated.completedAt = now()
            updated.updatedAt = now()
            try await records.save(updated)
            try await transition(recordID: recordID, to: .completed)
            emit(.sessionFinished(recordID: recordID, status: .completed))
            return
        }

        try await transition(recordID: recordID, to: .injecting)
        let snapshot = options.restoreClipboard ? await clipboard.save() : nil
        do {
            try await injector.insert(finalText)
            if let snapshot {
                // 恢复失败只记录诊断，不影响已完成输入（平台实现记日志）。
                try? await clipboard.restore(snapshot)
            }
            var updated = try await requireRecord(recordID)
            updated.completedAt = now()
            updated.updatedAt = now()
            try await records.save(updated)
            try await transition(recordID: recordID, to: .completed)
            emit(.sessionFinished(recordID: recordID, status: .completed))
        } catch let error as DictationError {
            // 输入失败：最终文字保留，可复制或手动再次输入。
            try? await transition(recordID: recordID, to: .injectionFailed, error: error)
            emit(.sessionFinished(recordID: recordID, status: .injectionFailed))
        } catch {
            let mapped = DictationError(
                category: .injectionTargetUnavailable,
                userMessage: "当前输入目标不可写入，请从历史记录复制文字"
            )
            try? await transition(recordID: recordID, to: .injectionFailed, error: mapped)
            emit(.sessionFinished(recordID: recordID, status: .injectionFailed))
        }
    }

    // MARK: - 重试

    /// 转录失败后使用原录音重新转录（HIST-004 服务入口）。
    public func retryTranscription(recordID: UUID) async throws {
        try guardIdle()
        guard let record = try await records.get(id: recordID) else { return }
        guard DictationStateMachine.canTransition(from: record.status, to: .transcribing) else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "当前状态不支持重新转录",
                isRetryable: false
            )
        }
        activeRecordID = recordID
        Task {
            defer { activeRecordID = nil }
            do {
                let rawText = try await performTranscription(recordID: recordID)
                let options = await (try? optionsProvider.currentOptions()) ?? PipelineOptions()
                var record = try await requireRecord(recordID)
                record.retryCount += 1
                record.updatedAt = now()
                try await records.save(record)

                let rewritePair = options.rewriteEnabled
                    ? try await providerFactory.makeRewriteProvider()
                    : nil
                if let (provider, snapshot) = rewritePair {
                    var updating = try await requireRecord(recordID)
                    updating.rewriteSnapshot = snapshot
                    updating.rewriteProfileID = snapshot.profileID
                    try await records.save(updating)
                    do {
                        let finalText = try await performRewrite(
                            recordID: recordID, originalText: rawText, provider: provider
                        )
                        try await saveFinalText(recordID: recordID, finalText: finalText)
                    } catch let error as DictationError {
                        try? await transition(recordID: recordID, to: .rewriteFailed, error: error)
                        emit(.sessionFinished(recordID: recordID, status: .rewriteFailed))
                        return
                    }
                } else {
                    try await saveFinalText(recordID: recordID, finalText: rawText)
                }
                try await transition(recordID: recordID, to: .ready)
                try await deliver(recordID: recordID, options: options)
            } catch {
                await emitTerminal(recordID: recordID)
            }
        }
    }

    /// 改写失败后仅重新改写，不重复上传音频。
    public func retryRewrite(recordID: UUID) async throws {
        try guardIdle()
        guard let record = try await records.get(id: recordID),
              let rawText = record.rawTranscript
        else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "缺少原始转录，无法重新改写",
                isRetryable: false
            )
        }
        guard record.status == .rewriteFailed else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "当前状态不支持重新改写",
                isRetryable: false
            )
        }
        guard let (provider, snapshot) = try await providerFactory.makeRewriteProvider() else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "尚未配置文字改写模型",
                isRetryable: false
            )
        }
        activeRecordID = recordID
        Task {
            defer { activeRecordID = nil }
            do {
                var updating = try await requireRecord(recordID)
                updating.rewriteSnapshot = snapshot
                updating.rewriteProfileID = snapshot.profileID
                updating.retryCount += 1
                updating.updatedAt = now()
                try await records.save(updating)
                do {
                    let finalText = try await performRewrite(
                        recordID: recordID, originalText: rawText, provider: provider
                    )
                    try await saveFinalText(recordID: recordID, finalText: finalText)
                } catch let error as DictationError {
                    try? await transition(recordID: recordID, to: .rewriteFailed, error: error)
                    emit(.sessionFinished(recordID: recordID, status: .rewriteFailed))
                    return
                }
                try await transition(recordID: recordID, to: .ready)
                let options = await (try? optionsProvider.currentOptions()) ?? PipelineOptions()
                try await deliver(recordID: recordID, options: options)
            } catch {
                await emitTerminal(recordID: recordID)
            }
        }
    }

    /// 输入失败后重新写入最终文字（HIST 页面「再次输入」入口）。
    ///
    /// 仅接受 `injectionFailed` 状态；最终文字与历史统计不受影响。
    public func retryInjection(recordID: UUID) async throws {
        try guardIdle()
        guard let record = try await records.get(id: recordID) else { return }
        guard record.status == .injectionFailed, record.finalText != nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "当前状态不支持重新输入",
                isRetryable: false
            )
        }
        activeRecordID = recordID
        Task {
            defer { activeRecordID = nil }
            do {
                // 用户显式再次输入：强制注入，不受当前自动输入开关影响。
                var options = await (try? optionsProvider.currentOptions()) ?? PipelineOptions()
                options.autoInsert = true
                try await deliver(recordID: recordID, options: options)
            } catch {
                await emitTerminal(recordID: recordID)
            }
        }
    }

    // MARK: - 内部

    private func guardIdle() throws {
        guard activeRecordID == nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "已有录音进行中，请稍后重试",
                isRetryable: false
            )
        }
    }

    private func transition(
        recordID: UUID,
        to target: DictationStatus,
        error: DictationError? = nil
    ) async throws {
        guard let current = try await records.get(id: recordID) else { return }
        try DictationStateMachine.validateTransition(from: current.status, to: target)
        try await records.updateStatus(id: recordID, status: target, error: error, at: now())
        emit(.statusChanged(recordID: recordID, status: target))
    }

    private func saveFinalText(recordID: UUID, finalText: String) async throws {
        var record = try await requireRecord(recordID)
        record.finalText = finalText
        record.countUnits = UnitCounter.count(finalText)
        record.updatedAt = now()
        try await records.save(record)
    }

    private func requireRecord(_ id: UUID) async throws -> DictationRecord {
        guard let record = try await records.get(id: id) else {
            throw DictationError(category: .unknown, userMessage: "记录不存在", isRetryable: false)
        }
        return record
    }

    /// 录音/文件阶段失败兜底：仅在仍处于早期状态时落库 recordingFailed。
    private func failRecordingStage(recordID: UUID, error: Any) async {
        guard let record = try? await records.get(id: recordID) else { return }
        guard record.status == .recording || record.status == .created else { return }
        let mapped = (error as? DictationError) ?? DictationError(
            category: .unknown,
            userMessage: "录音处理发生未知错误"
        )
        try? await transition(recordID: recordID, to: .recordingFailed, error: mapped)
    }

    private func emitTerminal(recordID: UUID) async {
        if let record = try? await records.get(id: recordID) {
            emit(.sessionFinished(recordID: recordID, status: record.status))
        }
    }

    private func emit(_ event: DictationSessionEvent) {
        eventContinuation?.yield(event)
    }
}
