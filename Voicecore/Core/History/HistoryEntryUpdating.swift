// HistoryEntryUpdating.swift
// Provides History Entry Updating for history storage and display support.

import Foundation

fileprivate enum HistoryEntryUpdate<Value> {
    case keep
    case set(Value)

    func resolved(current: Value) -> Value {
        switch self {
        case .keep:
            return current
        case .set(let value):
            return value
        }
    }
}

extension TranscriptionHistoryEntry {
    func updatingDictionaryCorrectionResult(
        text: String,
        dictionaryCorrectedTerms: [String],
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot]
    ) -> TranscriptionHistoryEntry {
        copy(
            text: text,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots
        )
    }

    func updatingDictionaryCorrectedTerms(_ dictionaryCorrectedTerms: [String]) -> TranscriptionHistoryEntry {
        copy(dictionaryCorrectedTerms: dictionaryCorrectedTerms)
    }

    func updatingDictionaryCorrectionSnapshots(_ dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot]) -> TranscriptionHistoryEntry {
        copy(dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots)
    }

    func updatingDictionarySuggestedTerms(_ dictionarySuggestedTerms: [DictionarySuggestionSnapshot]) -> TranscriptionHistoryEntry {
        copy(dictionarySuggestedTerms: dictionarySuggestedTerms)
    }

    func updatingTranscriptSummary(_ summary: TranscriptSummarySnapshot?) -> TranscriptionHistoryEntry {
        copy(
            transcriptSummary: .set(summary),
            transcriptSummaryStale: .set(false)
        )
    }

    func updatingTranscriptSummaryStale(_ isStale: Bool) -> TranscriptionHistoryEntry {
        copy(transcriptSummaryStale: .set(isStale))
    }

    func updatingSummaryChatMessages(_ summaryChatMessages: [TranscriptSummaryChatMessage]) -> TranscriptionHistoryEntry {
        copy(transcriptSummaryChatMessages: .set(summaryChatMessages))
    }

    func updatingTranscriptSegments(
        _ transcriptSegments: [TranscriptSegment],
        text: String
    ) -> TranscriptionHistoryEntry {
        copy(
            text: text,
            transcriptSegments: .set(transcriptSegments)
        )
    }

    func updatingTranscriptionChatMessages(_ transcriptionChatMessages: [TranscriptSummaryChatMessage]) -> TranscriptionHistoryEntry {
        copy(transcriptionChatMessages: .set(transcriptionChatMessages))
    }

    func updatingTranscriptionEntry(
        text: String,
        createdAt: Date,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        whisperWordTimings: [WhisperHistoryWordTiming]?,
        senseVoiceMetadata: SenseVoiceTranscriptMetadata?,
        transcriptionChatMessages: [TranscriptSummaryChatMessage],
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot],
        status: TranscriptionHistoryStatus = .completed,
        failureReason: String? = nil
    ) -> TranscriptionHistoryEntry {
        copy(
            text: text,
            createdAt: createdAt,
            audioDurationSeconds: .set(audioDurationSeconds),
            transcriptionProcessingDurationSeconds: .set(transcriptionProcessingDurationSeconds),
            llmDurationSeconds: .set(llmDurationSeconds),
            whisperWordTimings: .set(whisperWordTimings),
            senseVoiceMetadata: .set(senseVoiceMetadata),
            transcriptionChatMessages: .set(transcriptionChatMessages),
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots,
            dictionarySuggestedTerms: dictionarySuggestedTerms,
            status: .set(status),
            failureReason: .set(failureReason)
        )
    }

    /// Updates only the status of an entry, preserving every other field as-is. Used when a
    /// retry attempt fails again (e.g. ASR retry still fails) and the failed entry/audio should
    /// be kept in place with an updated status rather than replaced or discarded.
    func updatingStatus(
        _ status: TranscriptionHistoryStatus,
        failureReason: String? = nil
    ) -> TranscriptionHistoryEntry {
        copy(status: .set(status), failureReason: .set(failureReason))
    }

    func updatingAudioRelativePath(_ audioRelativePath: String?) -> TranscriptionHistoryEntry {
        copy(audioRelativePath: .set(audioRelativePath))
    }

    func updatingOutputDestination(
        focusedAppName: String?,
        focusedAppBundleID: String?,
        browserURLHost: String?,
        browserURLOrigin: String?
    ) -> TranscriptionHistoryEntry {
        copy(
            focusedAppName: .set(focusedAppName),
            focusedAppBundleID: .set(focusedAppBundleID),
            browserURLHost: .set(browserURLHost),
            browserURLOrigin: .set(browserURLOrigin)
        )
    }

    private func copy(
        text: String? = nil,
        createdAt: Date? = nil,
        audioDurationSeconds: HistoryEntryUpdate<TimeInterval?> = .keep,
        transcriptionProcessingDurationSeconds: HistoryEntryUpdate<TimeInterval?> = .keep,
        llmDurationSeconds: HistoryEntryUpdate<TimeInterval?> = .keep,
        focusedAppName: HistoryEntryUpdate<String?> = .keep,
        focusedAppBundleID: HistoryEntryUpdate<String?> = .keep,
        browserURLHost: HistoryEntryUpdate<String?> = .keep,
        browserURLOrigin: HistoryEntryUpdate<String?> = .keep,
        audioRelativePath: HistoryEntryUpdate<String?> = .keep,
        whisperWordTimings: HistoryEntryUpdate<[WhisperHistoryWordTiming]?> = .keep,
        senseVoiceMetadata: HistoryEntryUpdate<SenseVoiceTranscriptMetadata?> = .keep,
        transcriptSegments: HistoryEntryUpdate<[TranscriptSegment]?> = .keep,
        transcriptSummary: HistoryEntryUpdate<TranscriptSummarySnapshot?> = .keep,
        transcriptSummaryStale: HistoryEntryUpdate<Bool> = .keep,
        transcriptSummaryChatMessages: HistoryEntryUpdate<[TranscriptSummaryChatMessage]?> = .keep,
        transcriptionChatMessages: HistoryEntryUpdate<[TranscriptSummaryChatMessage]?> = .keep,
        dictionaryHitTerms: [String]? = nil,
        dictionaryCorrectedTerms: [String]? = nil,
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot]? = nil,
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]? = nil,
        status: HistoryEntryUpdate<TranscriptionHistoryStatus> = .keep,
        failureReason: HistoryEntryUpdate<String?> = .keep
    ) -> TranscriptionHistoryEntry {
        let resolvedText = text ?? self.text
        let resolvedCreatedAt = createdAt ?? self.createdAt
        let resolvedAudioDurationSeconds = audioDurationSeconds.resolved(current: self.audioDurationSeconds)
        let resolvedTranscriptionProcessingDurationSeconds = transcriptionProcessingDurationSeconds.resolved(
            current: self.transcriptionProcessingDurationSeconds
        )
        let resolvedLLMDurationSeconds = llmDurationSeconds.resolved(current: self.llmDurationSeconds)
        let resolvedFocusedAppName = focusedAppName.resolved(current: self.focusedAppName)
        let resolvedFocusedAppBundleID = focusedAppBundleID.resolved(current: self.focusedAppBundleID)
        let resolvedBrowserURLHost = browserURLHost.resolved(current: self.browserURLHost)
        let resolvedBrowserURLOrigin = browserURLOrigin.resolved(current: self.browserURLOrigin)
        let resolvedAudioRelativePath = audioRelativePath.resolved(current: self.audioRelativePath)
        let resolvedWhisperWordTimings = whisperWordTimings.resolved(current: self.whisperWordTimings)
        let resolvedSenseVoiceMetadata = senseVoiceMetadata.resolved(current: self.senseVoiceMetadata)
        let resolvedTranscriptSegments = transcriptSegments.resolved(current: self.transcriptSegments)
        let resolvedTranscriptSummary = transcriptSummary.resolved(current: self.transcriptSummary)
        let resolvedTranscriptSummaryStale = transcriptSummaryStale.resolved(current: self.transcriptSummaryStale)
        let resolvedTranscriptSummaryChatMessages = transcriptSummaryChatMessages.resolved(
            current: self.transcriptSummaryChatMessages
        )
        let resolvedTranscriptionChatMessages = transcriptionChatMessages.resolved(current: self.transcriptionChatMessages)
        let resolvedDictionaryHitTerms = dictionaryHitTerms ?? self.dictionaryHitTerms
        let resolvedDictionaryCorrectedTerms = dictionaryCorrectedTerms ?? self.dictionaryCorrectedTerms
        let resolvedDictionaryCorrectionSnapshots = dictionaryCorrectionSnapshots ?? self.dictionaryCorrectionSnapshots
        let resolvedDictionarySuggestedTerms = dictionarySuggestedTerms ?? self.dictionarySuggestedTerms
        let resolvedStatus = status.resolved(current: self.resolvedStatus)
        let resolvedFailureReason = failureReason.resolved(current: self.failureReason)

        return TranscriptionHistoryEntry(
            id: id,
            text: resolvedText,
            createdAt: resolvedCreatedAt,
            transcriptionEngine: transcriptionEngine,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode,
            enhancementModel: enhancementModel,
            kind: kind,
            isTranslation: isTranslation,
            audioDurationSeconds: resolvedAudioDurationSeconds,
            transcriptionProcessingDurationSeconds: resolvedTranscriptionProcessingDurationSeconds,
            llmDurationSeconds: resolvedLLMDurationSeconds,
            focusedAppName: resolvedFocusedAppName,
            focusedAppBundleID: resolvedFocusedAppBundleID,
            browserURLHost: resolvedBrowserURLHost,
            browserURLOrigin: resolvedBrowserURLOrigin,
            matchedGroupID: matchedGroupID,
            matchedGroupName: matchedGroupName,
            matchedAppGroupName: matchedAppGroupName,
            matchedURLGroupName: matchedURLGroupName,
            remoteASRProvider: remoteASRProvider,
            remoteASRModel: remoteASRModel,
            remoteASREndpoint: remoteASREndpoint,
            remoteLLMProvider: remoteLLMProvider,
            remoteLLMModel: remoteLLMModel,
            remoteLLMEndpoint: remoteLLMEndpoint,
            audioRelativePath: resolvedAudioRelativePath,
            whisperWordTimings: resolvedWhisperWordTimings,
            senseVoiceMetadata: resolvedSenseVoiceMetadata,
            transcriptSegments: resolvedTranscriptSegments,
            transcriptAudioRelativePath: transcriptAudioRelativePath,
            meetingCaptureMode: meetingCaptureMode,
            transcriptSummary: resolvedTranscriptSummary,
            transcriptSummaryStale: resolvedTranscriptSummaryStale,
            transcriptSummaryChatMessages: resolvedTranscriptSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: resolvedTranscriptionChatMessages,
            dictionaryHitTerms: resolvedDictionaryHitTerms,
            dictionaryCorrectedTerms: resolvedDictionaryCorrectedTerms,
            dictionaryCorrectionSnapshots: resolvedDictionaryCorrectionSnapshots,
            dictionarySuggestedTerms: resolvedDictionarySuggestedTerms,
            status: resolvedStatus,
            failureReason: resolvedFailureReason
        )
    }
}
