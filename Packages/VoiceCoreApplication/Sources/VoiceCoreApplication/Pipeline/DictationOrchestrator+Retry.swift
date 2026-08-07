import Foundation
import VoiceCoreDomain

/// 重试入口：转录失败重转录、改写失败仅重写、输入失败再次输入。
extension DictationOrchestrator {
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
            await runTranscriptionRetry(recordID: recordID)
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
            await runRewriteRetry(
                recordID: recordID,
                rawText: rawText,
                provider: provider,
                snapshot: snapshot
            )
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

    // MARK: - 后台任务体

    /// 重新转录后台流程：转录成功后续走可选改写与自动输入。
    private func runTranscriptionRetry(recordID: UUID) async {
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
                try await runRewriteStage(
                    recordID: recordID,
                    rawText: rawText,
                    provider: provider,
                    snapshot: snapshot,
                    bumpRetryCount: false
                )
            } else {
                try await saveFinalText(recordID: recordID, finalText: rawText)
                try await transition(recordID: recordID, to: .ready)
                try await deliver(recordID: recordID, options: options)
            }
        } catch {
            await emitTerminal(recordID: recordID)
        }
    }

    /// 重新改写后台流程：更新快照与计数后仅执行改写阶段。
    private func runRewriteRetry(
        recordID: UUID,
        rawText: String,
        provider: any RewriteProvider,
        snapshot: ProviderProfileSnapshot
    ) async {
        do {
            try await runRewriteStage(
                recordID: recordID,
                rawText: rawText,
                provider: provider,
                snapshot: snapshot,
                bumpRetryCount: true
            )
        } catch {
            await emitTerminal(recordID: recordID)
        }
    }

    /// 改写阶段共用体：写快照 → 改写 → 存最终文字 → ready → 自动输入。
    /// 改写失败落库 rewriteFailed 并正常返回（不发 ready）。
    private func runRewriteStage(
        recordID: UUID,
        rawText: String,
        provider: any RewriteProvider,
        snapshot: ProviderProfileSnapshot,
        bumpRetryCount: Bool
    ) async throws {
        var updating = try await requireRecord(recordID)
        updating.rewriteSnapshot = snapshot
        updating.rewriteProfileID = snapshot.profileID
        if bumpRetryCount {
            updating.retryCount += 1
        }
        updating.updatedAt = now()
        try await records.save(updating)
        do {
            let finalText = try await performRewrite(
                recordID: recordID,
                originalText: rawText,
                provider: provider
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
    }
}
