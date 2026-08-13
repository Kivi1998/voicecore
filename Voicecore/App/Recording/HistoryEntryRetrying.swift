// HistoryEntryRetrying.swift
// Regenerates any history entry from its archived audio file.

import Foundation

enum HistoryRetryPhase: Equatable, Sendable {
    case queued
    case preparingAudio
    case recognizingSpeech
    case enhancingText

    var localizedTitle: String {
        switch self {
        case .queued:
            return AppLocalization.localizedString("Waiting to retry")
        case .preparingAudio:
            return AppLocalization.localizedString("Preparing original recording")
        case .recognizingSpeech:
            return AppLocalization.localizedString("Recognizing speech")
        case .enhancingText:
            return AppLocalization.localizedString("Enhancing text")
        }
    }
}

private actor HistoryRetryConcurrencyLimiter {
    private let maximumConcurrentRetries = 2
    private var activeRetryCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if activeRetryCount < maximumConcurrentRetries {
            activeRetryCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeRetryCount = max(0, activeRetryCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private nonisolated final class HistoryRetryTimingCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [VoiceCoreNetworkSession.RequestTiming] = []

    func append(_ timing: VoiceCoreNetworkSession.RequestTiming) {
        lock.lock()
        values.append(timing)
        lock.unlock()
    }

    func summary() -> String {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot.map(\.logSummary).joined(separator: " | ")
    }
}

extension AppDelegate {
    private static let historyRetryLimiter = HistoryRetryConcurrencyLimiter()

    enum HistoryRetryError: LocalizedError {
        case entryNotFound
        case audioMissing
        case asrNotConfigured
        case enhancementRetryFailed(String)

        var errorDescription: String? {
            switch self {
            case .entryNotFound:
                return AppLocalization.localizedString("The history entry could not be found.")
            case .audioMissing:
                return AppLocalization.localizedString("The original recording is missing, so this entry cannot be retried.")
            case .asrNotConfigured:
                return AppLocalization.localizedString("The selected ASR model is not configured.")
            case .enhancementRetryFailed(let message):
                return message
            }
        }
    }

    /// Regenerates transcription and its feature-specific text transform using the archived
    /// archived audio file. On success the existing entry is updated in place (no duplicate
    /// entry is created). On failure the entry and its audio are left untouched, with the
    /// status updated so the user can retry again.
    @MainActor
    @discardableResult
    func retryHistoryEntry(
        _ entryID: UUID,
        onPhaseChange: @MainActor @escaping (HistoryRetryPhase) -> Void = { _ in }
    ) async throws -> TranscriptionHistoryEntry {
        onPhaseChange(.queued)
        await Self.historyRetryLimiter.acquire()
        defer {
            Task { await Self.historyRetryLimiter.release() }
        }
        onPhaseChange(.preparingAudio)

        guard let existingEntry = historyStore.entry(id: entryID) else {
            throw HistoryRetryError.entryNotFound
        }
        guard let audioURL = historyStore.audioURL(for: existingEntry),
              FileManager.default.fileExists(atPath: audioURL.path)
        else {
            throw HistoryRetryError.audioMissing
        }

        do {
            let asrSelectionID = historyASRSelectionID(for: existingEntry.kind)
            guard case .remote(let provider)? = asrSelectionID.asrSelection else {
                throw HistoryRetryError.asrNotConfigured
            }
            let storedConfigurations = RemoteModelConfigurationStore.loadConfigurations(
                from: UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? "",
                sensitiveValueLoading: .includeStoredValues
            )
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: storedConfigurations
            )
            guard configuration.isConfigured else {
                throw HistoryRetryError.asrNotConfigured
            }
            async let asrWarmup: Void = VoiceCoreNetworkSession.prewarmTransport(
                endpoint: historyASREndpoint(provider: provider, configuration: configuration)
            )
            async let llmWarmup: Void = prewarmHistoryLLMTransport(for: existingEntry.kind)
            _ = await (asrWarmup, llmWarmup)

            let timingCollector = HistoryRetryTimingCollector()
            let asrStartedAt = Date()
            onPhaseChange(.recognizingSpeech)
            let rawText = try await VoiceCoreNetworkSession.$requestTimingObserver.withValue({ timing in
                timingCollector.append(timing)
            }) {
                try await remoteASRTranscriber.transcribeDebugAudioFile(
                    audioURL,
                    provider: provider,
                    configuration: configuration
                )
            }
            let asrDurationSeconds = Date().timeIntervalSince(asrStartedAt)

            let trimmedRawText = rawText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedRawText.isEmpty else {
                // ASR completed but produced nothing usable again — keep this a retryable
                // ASR failure rather than silently losing the record.
                if let updated = historyStore.updateStatus(
                    entryID,
                    status: .asrFailed,
                    failureReason: AppLocalization.localizedString("The ASR model returned empty text.")
                ) {
                    return updated
                }
                throw HistoryRetryError.entryNotFound
            }

            let enhancedText: String
            let llmDurationSeconds: TimeInterval?
            do {
                let enhanceStartedAt = Date()
                onPhaseChange(.enhancingText)
                enhancedText = try await VoiceCoreNetworkSession.$requestTimingObserver.withValue({ timing in
                    timingCollector.append(timing)
                }) {
                    try await regenerateHistoryText(trimmedRawText, kind: existingEntry.kind)
                }
                llmDurationSeconds = Date().timeIntervalSince(enhanceStartedAt)
            } catch {
                VoiceCoreLog.asrWarning("History retry enhancement failed; keeping entry retryable. entryID=\(entryID.uuidString), error=\(error.localizedDescription)")
                _ = historyStore.updateTranscriptionEntry(
                    entryID,
                    text: trimmedRawText,
                    createdAt: existingEntry.createdAt,
                    audioDurationSeconds: existingEntry.audioDurationSeconds,
                    transcriptionProcessingDurationSeconds: asrDurationSeconds,
                    llmDurationSeconds: nil,
                    whisperWordTimings: nil,
                    senseVoiceMetadata: nil,
                    transcriptionChatMessages: [],
                    dictionaryHitTerms: [],
                    dictionaryCorrectedTerms: [],
                    dictionarySuggestedTerms: [],
                    status: .enhancementFailed,
                    failureReason: error.localizedDescription
                )
                throw HistoryRetryError.enhancementRetryFailed(error.localizedDescription)
            }

            guard let updated = historyStore.updateTranscriptionEntry(
                entryID,
                text: enhancedText,
                createdAt: existingEntry.createdAt,
                audioDurationSeconds: existingEntry.audioDurationSeconds,
                transcriptionProcessingDurationSeconds: asrDurationSeconds,
                llmDurationSeconds: llmDurationSeconds,
                whisperWordTimings: existingEntry.whisperWordTimings,
                senseVoiceMetadata: existingEntry.senseVoiceMetadata,
                transcriptionChatMessages: existingEntry.transcriptionChatMessages ?? [],
                dictionaryHitTerms: [],
                dictionaryCorrectedTerms: [],
                dictionaryCorrectionSnapshots: [],
                dictionarySuggestedTerms: [],
                status: .completed,
                failureReason: nil
            ) else {
                throw HistoryRetryError.entryNotFound
            }
            VoiceCoreLog.network(
                "History retry timing. entryID=\(entryID.uuidString), asrTotalMs=\(Int(asrDurationSeconds * 1_000)), llmTotalMs=\(Int((llmDurationSeconds ?? 0) * 1_000)), requests=[\(timingCollector.summary())]"
            )
            return updated
        } catch let retryError as HistoryRetryError {
            switch retryError {
            case .enhancementRetryFailed:
                break
            case .entryNotFound:
                break
            case .audioMissing, .asrNotConfigured:
                _ = historyStore.updateStatus(
                    entryID,
                    status: .asrFailed,
                    failureReason: retryError.localizedDescription
                )
            }
            throw retryError
        } catch {
            // ASR (or the meeting-configuration lookup) failed again — keep the failed entry
            // and its audio around for another retry instead of discarding them.
            VoiceCoreLog.asrWarning("History retry ASR failed. entryID=\(entryID.uuidString), error=\(error.localizedDescription)")
            _ = historyStore.updateStatus(
                entryID,
                status: .asrFailed,
                failureReason: error.localizedDescription
            )
            throw error
        }
    }

    @MainActor
    func prewarmConfiguredHistoryRetryTransports() async {
        let asrStored = remoteASRConfigurations
        let llmStored = remoteLLMConfigurations
        var endpoints = Set<String>()
        for provider in RemoteASRProvider.allCases {
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: asrStored
            )
            guard configuration.isConfigured else { continue }
            endpoints.insert(historyASREndpoint(provider: provider, configuration: configuration))
        }
        let runtimeClient = RemoteLLMRuntimeClient()
        for provider in RemoteLLMProvider.allCases {
            guard RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: llmStored
            ) else { continue }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: llmStored
            )
            endpoints.insert(runtimeClient.resolvedLLMEndpoint(
                provider: provider,
                endpoint: configuration.endpoint,
                model: configuration.model
            ))
        }
        await withTaskGroup(of: Void.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await VoiceCoreNetworkSession.prewarmTransport(endpoint: endpoint)
                }
            }
        }
    }

    private func prewarmHistoryLLMTransport(for kind: TranscriptionHistoryKind) async {
        guard let selection = historyLLMSelectionID(for: kind),
              case .remoteLLM(let provider)? = selection.textSelection
        else { return }
        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        guard configuration.isConfigured else { return }
        let endpoint = RemoteLLMRuntimeClient().resolvedLLMEndpoint(
            provider: provider,
            endpoint: configuration.endpoint,
            model: configuration.model
        )
        await VoiceCoreNetworkSession.prewarmTransport(endpoint: endpoint)
    }

    private func historyLLMSelectionID(for kind: TranscriptionHistoryKind) -> FeatureModelSelectionID? {
        switch kind {
        case .normal:
            return transcriptionFeatureSettings.llmEnabled ? transcriptionFeatureSettings.llmSelectionID : nil
        case .translation:
            return translationFeatureSettings.modelSelectionID
        case .rewrite:
            return rewriteFeatureSettings.llmSelectionID
        case .transcript:
            return nil
        }
    }

    private func historyASREndpoint(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        switch provider {
        case .openAIWhisper:
            return RemoteProviderConnectivityTestEndpoints.resolvedASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://api.openai.com/v1/audio/transcriptions"
            )
        case .doubaoASR:
            return DoubaoASRConfiguration.resolvedFlashRecognitionEndpoint(configuration.endpoint)
        case .glmASR:
            return RemoteProviderConnectivityTestEndpoints.resolvedGLMASRTranscriptionEndpoint(
                endpoint: configuration.endpoint,
                defaultValue: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions"
            )
        case .aliyunBailianASR:
            return AliyunRemoteASRConfiguration.resolvedTranscriptionEndpoint(
                configuration.endpoint,
                model: configuration.model
            )
        case .stepFunASR:
            return RemoteProviderConnectivityTestEndpoints.resolvedStepFunASREndpoint(configuration.endpoint)
        case .xiaomiMiMoASR:
            return RemoteProviderConnectivityTestEndpoints.resolvedXiaomiMiMoASREndpoint(configuration.endpoint)
        }
    }

    private func historyASRSelectionID(for kind: TranscriptionHistoryKind) -> FeatureModelSelectionID {
        switch kind {
        case .normal:
            return transcriptionFeatureSettings.asrSelectionID
        case .translation:
            return translationFeatureSettings.asrSelectionID
        case .rewrite:
            return rewriteFeatureSettings.asrSelectionID
        case .transcript:
            return FeatureSettingsStore.load().meeting.asrSelectionID
        }
    }

    private func regenerateHistoryText(
        _ rawText: String,
        kind: TranscriptionHistoryKind
    ) async throws -> String {
        prepareLegacySettingsForSession(outputMode: historyOutputMode(for: kind))
        switch kind {
        case .normal, .transcript:
            return try await enhanceTextForCurrentMode(rawText, sessionID: nil)
        case .translation:
            return try await translateText(
                rawText,
                targetLanguage: translationTargetLanguage
            )
        case .rewrite:
            return try await runRewritePreview(dictatedPrompt: rawText, sourceText: "")
        }
    }

    private func historyOutputMode(for kind: TranscriptionHistoryKind) -> SessionOutputMode {
        switch kind {
        case .normal, .transcript:
            return .transcription
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        }
    }
}
