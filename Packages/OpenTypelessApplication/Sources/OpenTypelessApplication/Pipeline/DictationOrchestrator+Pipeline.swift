import Foundation
import OpenTypelessDomain

/// 转录前置上下文：提供商、记录与录音相对路径。
private struct TranscriptionContext {
    let provider: any SpeechProvider
    let record: DictationRecord
    let relativePath: String
}

/// 主流水线：录音收尾 → 转录 → 可选改写 → 自动输入。
extension DictationOrchestrator {
    func runPipeline(recordID: UUID) async {
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
    func performTranscription(recordID: UUID) async throws -> String {
        let context = try await transcriptionContext(recordID: recordID)
        let record = context.record
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
            let result = try await requestTranscription(
                provider: context.provider,
                record: record,
                relativePath: context.relativePath,
                options: options,
                attemptID: attempt.id
            )
            attempt.success = true
            attempt.finishedAt = now()
            attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
            attempt.providerRequestID = result.providerRequestID
            try await records.saveAttempt(attempt)

            // 必须基于最新记录改写字段：直接使用转录前读取的旧记录，
            // 整行 save 会把状态写回 audioSaved，导致 transcribing→transcribed
            // 被判为非法迁移（testFullPipelineWithRewriteCompletes 等曾因此停滞）。
            var updated = try await requireRecord(recordID)
            updated.rawTranscript = result.text
            updated.detectedLanguage = result.detectedLanguage
            updated.updatedAt = now()
            try await records.save(updated)
            try await transition(recordID: recordID, to: .transcribed)
            return result.text
        } catch {
            let mapped = mapStageError(error, unknownMessage: "转录发生未知错误", cancelMessage: "转录已取消")
            await failAttempt(&attempt, error: mapped)
            try? await transition(recordID: recordID, to: .transcriptionFailed, error: mapped)
            if error is CancellationError {
                throw CancellationError()
            }
            throw mapped
        }
    }

    /// 转录前置校验：提供商配置与录音文件齐备；失败落库 transcriptionFailed。
    private func transcriptionContext(
        recordID: UUID
    ) async throws -> TranscriptionContext {
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
        return TranscriptionContext(provider: provider, record: record, relativePath: relativePath)
    }

    /// 发起一次转录请求；长音频允许更长总超时：基础 60 秒 + 每 2 秒音频增加 1 秒，封顶 600。
    private func requestTranscription(
        provider: any SpeechProvider,
        record: DictationRecord,
        relativePath: String,
        options: PipelineOptions,
        attemptID: UUID
    ) async throws -> SpeechResult {
        let vocabulary = await (try? providerFactory.vocabularyTerms()) ?? []
        let timeout = min(600, 60 + TimeInterval(record.durationMs) / 1000 / 2)
        return try await provider.transcribe(SpeechRequest(
            audioFile: audioURLResolver(relativePath),
            mimeType: record.audioMimeType ?? "audio/mp4",
            durationMs: record.durationMs,
            languageHint: options.languageHint,
            vocabularyTerms: vocabulary,
            timeoutSeconds: timeout,
            recordID: record.id,
            attemptID: attemptID
        ))
    }

    /// 改写阶段（含尝试记录写回）；成功返回最终文字。
    func performRewrite(
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
        } catch {
            let mapped = mapStageError(error, unknownMessage: "改写发生未知错误", cancelMessage: "改写已取消")
            await failAttempt(&attempt, error: mapped)
            throw mapped
        }
    }

    /// 自动输入与剪贴板恢复编排；输入失败不丢文本。
    func deliver(recordID: UUID, options: PipelineOptions) async throws {
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

    /// 阶段错误标准化：保留 DictationError，映射取消与未知错误。
    func mapStageError(_ error: any Error, unknownMessage: String, cancelMessage: String) -> DictationError {
        if let dictationError = error as? DictationError {
            return dictationError
        }
        if error is CancellationError {
            return DictationError(category: .unknown, userMessage: cancelMessage, isRetryable: false)
        }
        return DictationError(category: .unknown, userMessage: unknownMessage)
    }

    /// 失败尝试写回（成功路径在各阶段内联处理）。
    func failAttempt(_ attempt: inout RecordAttempt, error: DictationError) async {
        attempt.success = false
        attempt.finishedAt = now()
        attempt.latencyMs = Int64(now().timeIntervalSince(attempt.startedAt) * 1000)
        attempt.errorCategory = error.category
        attempt.errorMessage = error.userMessage
        try? await records.saveAttempt(attempt)
    }
}
