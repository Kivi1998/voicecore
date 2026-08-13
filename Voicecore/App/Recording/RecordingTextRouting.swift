// RecordingTextRouting.swift
// Provides Recording Text Routing for recording session routing.

import Foundation

extension AppDelegate {
    func handleLiveASRPartialTranscription(_ rawText: String, sessionID: UUID) {
        guard shouldHandleCallbacks(for: sessionID) else { return }
        let displayText = RecordingSessionSupport.normalizedTranscriptionDisplayText(
            rawText,
            transcriptionEngine: transcriptionEngine,
            remoteProvider: remoteASRSelectedProvider,
            userMainLanguage: userMainLanguage
        )
        let text = sanitizedFinalTranscriptionText(displayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recordLiveASRPartialTranscription(text, sessionID: sessionID)
    }

    private func recordLiveASRPartialTranscription(_ text: String, sessionID: UUID) {
        guard recordingStoppedAt == nil else { return }
        guard transcriptionCapturePipeline.usesLiveDisplay else { return }
        guard sessionOutputMode == .transcription else { return }

        let isFirstLivePartial = firstLiveASRPartialReceivedAt == nil
        if isFirstLivePartial {
            firstLiveASRPartialReceivedAt = Date()
            VoiceCoreLog.asr(
                "Live ASR partial received. sessionID=\(sessionID.uuidString), chars=\(text.count), pipeline=\(transcriptionCapturePipeline.rawValue)",
                verbose: true
            )
        }

        if transcriptionCapturePipeline == .noteSession {
            refreshVoiceCoreNoteTranscriptDisplay()
        }
    }

    func processTranscription(_ rawText: String) {
        processTranscription(rawText, sessionID: activeRecordingSessionID)
    }

    func processTranscription(_ rawText: String, sessionID: UUID) {
        let callbackDecision = Self.sessionCallbackHandlingDecision(
            requestedSessionID: sessionID,
            activeSessionID: activeRecordingSessionID,
            isSessionCancellationRequested: isSessionCancellationRequested
        )
        guard callbackDecision == .accept else {
            VoiceCoreLog.asr(
                """
                Dropping transcription callback before processing. reason=\(callbackDecision.logDescription), callbackSessionID=\(sessionID.uuidString), activeSessionID=\(activeRecordingSessionID.uuidString), stopped=\(recordingStoppedAt != nil), endingSessionID=\(currentEndingSessionID?.uuidString ?? "nil"), rawChars=\(rawText.count)
                """,
                verbose: true
            )
            return
        }
        if didCommitSessionOutput {
            VoiceCoreLog.asr("Ignoring transcription callback because current session output has already been committed.")
            return
        }

        transcriptionResultReceivedAt = Date()
        if let stoppedAt = recordingStoppedAt {
            let stopToResultMs = max(Int(Date().timeIntervalSince(stoppedAt) * 1000), 0)
            VoiceCoreLog.asr(
                "Transcription callback accepted after stop. sessionID=\(sessionID.uuidString), stopToResultMs=\(stopToResultMs), rawChars=\(rawText.count)",
                verbose: true
            )
        }
        let displayText = RecordingSessionSupport.normalizedTranscriptionDisplayText(
            rawText,
            transcriptionEngine: transcriptionEngine,
            remoteProvider: remoteASRSelectedProvider,
            userMainLanguage: userMainLanguage
        )
        let text = sanitizedFinalTranscriptionText(displayText)
        if shouldSuppressFinalTranscriptionForLocalVAD(text) {
            VoiceCoreLog.asr(
                "Transcription result suppressed because local VAD observed no speech. chars=\(text.count)",
                verbose: true
            )
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }
        guard !text.isEmpty else {
            if let runtimeFailureMessage = consumeActiveRecordingRuntimeFailureMessage() {
                if isCurrentTranscriptionNoteSessionActive {
                    _ = captureTrailingVoiceCoreNoteIfNeeded(finalRawText: currentSessionRawTranscribedText())
                } else {
                    // ASR failed (e.g. network/TLS error) but the raw recording was already
                    // archived — keep it as a retryable failed history entry instead of
                    // silently discarding it. "No speech detected" does not reach this branch
                    // (it never sets a runtime failure message), so it's not misclassified here.
                    let failedEntryID = appendHistoryIfNeeded(
                        text: "",
                        outputMode: sessionOutputMode,
                        outputDestinationContext: captureCurrentOutputDestinationContext(),
                        llmDurationSeconds: nil,
                        dictionaryHitTerms: [],
                        dictionaryCorrectedTerms: [],
                        dictionarySuggestedTerms: [],
                        status: .asrFailed,
                        failureReason: runtimeFailureMessage
                    )
                    overlayState.latestHistoryEntryID = failedEntryID
                }
                VoiceCoreLog.asrWarning(
                    "Transcription result is empty because runtime inference failed. message=\(runtimeFailureMessage)"
                )
                showOverlayStatus(runtimeFailureMessage, clearAfter: 2.4)
                setEnhancingState(false)
                finishSession(after: 2.4)
                return
            }
            if isCurrentTranscriptionNoteSessionActive {
                _ = captureTrailingVoiceCoreNoteIfNeeded(finalRawText: currentSessionRawTranscribedText())
            } else {
                VoiceCoreLog.asr("Transcription result is empty; finishing session.")
            }
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        updateActiveRecordingTranscriberTranscribedText(text)
        refreshVoiceCoreNoteTranscriptDisplay()

        VoiceCoreLog.asr("Transcription result received. characters=\(text.count), output=\(sessionOutputMode == .translation ? "translation" : "transcription")")
        VoiceCoreLog.asr("Transcription result output mode resolved as \(RecordingSessionSupport.outputLabel(for: sessionOutputMode)).", verbose: true)
        VoiceCoreLog.model(
            "Session text model routing: \(RecordingSessionSupport.textModelRoutingDescription(outputMode: sessionOutputMode, transcriptionSettings: transcriptionFeatureSettings, translationSettings: translationFeatureSettings, rewriteSettings: rewriteFeatureSettings))"
        )

        if sessionOutputMode == .translation {
            processTranslatedTranscription(text, sessionID: sessionID)
            return
        }

        if sessionOutputMode == .rewrite {
            processRewriteTranscription(text, sessionID: sessionID)
            return
        }

        if isCurrentTranscriptionNoteSessionActive {
            _ = captureTrailingVoiceCoreNoteIfNeeded(finalRawText: text)
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        VoiceCoreLog.asr("Transcription flow dispatch: standard. characters=\(text.count), enhancementMode=\(enhancementMode.rawValue)", verbose: true)
        processStandardTranscription(text, sessionID: sessionID)
    }

    private func shouldSuppressFinalTranscriptionForLocalVAD(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let localVADMode = LocalVADMode.stored()
        let localVADGatePolicy = ASRVoiceActivityRuntimePolicy.localGatePolicy(
            transcriptionEngine: transcriptionEngine,
            mode: localVADMode
        )
        return ASRVoiceActivityRuntimePolicy.shouldSuppressFinalTranscription(
            localVADGateActive: localVADGatePolicy.isEnabled,
            observedVoiceActivityFrames: localVADObservedFramesInCurrentSession,
            observedSpeech: localVADObservedSpeechInCurrentSession
        )
    }

    func startPauseLLMIfNeeded() {
        runPauseEnhancementIfNeeded()
    }
}
