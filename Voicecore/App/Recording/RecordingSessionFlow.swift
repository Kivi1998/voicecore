// RecordingSessionFlow.swift
// Provides Recording Session Flow for recording session routing.

import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
    func continueRewriteConversation() {
        guard overlayState.canContinueRewriteAnswer else { return }
        overlayState.beginRewriteConversationIfNeeded()
        beginRecording(outputMode: .rewrite)
    }

    func releaseResidualRecordingResources(
        reason: String,
        preservePendingHistoryAudio: Bool = false
    ) {
        let speechWasRecording = speechTranscriber.isRecording
        let remoteWasRecording = remoteASRTranscriber.isRecording

        if speechWasRecording || remoteWasRecording {
            VoiceCoreLog.asrWarning(
                """
                Releasing residual recording resources. reason=\(reason), speech=\(speechWasRecording), remote=\(remoteWasRecording)
                """
            )
        }

        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        _ = cancelRecordingCaptureStartTask()

        speechTranscriber.stopRecording()
        remoteASRTranscriber.discardPendingSessionOutput()
        if preservePendingHistoryAudio {
            VoiceCoreLog.asr("Preserving pending history audio during residual resource release. reason=\(reason)", verbose: true)
        } else {
            discardPendingCompletedHistoryAudio()
        }

        overlayState.isRecording = false
        overlayState.isRewriteConversationTurnInProgress = false
        overlayState.audioLevel = 0
    }

    func toggleRewriteConversationRecording() {
        guard overlayState.isRewriteConversationActive else { return }
        if isSessionActive {
            endRecording()
        } else {
            beginRecording(outputMode: .rewrite)
        }
    }

    func beginRecording(
        outputMode: SessionOutputMode,
        transcriptionCaptureMode: TranscriptionCaptureSessionMode = .standard
    ) {
        guard !isApplicationTerminating else { return }
        let availability = FeatureSettingsStore.availability()
        switch outputMode {
        case .transcription:
            if transcriptionCaptureMode == .noteSession, !availability.notesEnabled {
                return
            }
        case .translation:
            guard availability.translationEnabled else { return }
        case .rewrite:
            guard availability.rewriteEnabled else { return }
        }
        let transcriptionHotkeyStartBehavior = outputMode == .transcription
            ? pendingTranscriptionHotkeyStartBehavior
            : nil
        if outputMode == .transcription {
            pendingTranscriptionHotkeyStartBehavior = nil
        }

        recordingRequestedAt = Date()
        VoiceCoreLog.asr(
            "Begin recording requested. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), isSessionActive=\(isSessionActive)",
            verbose: true
        )
        guard !blockNonMeetingRecordingWhileMeetingIsActive(
            source: "beginRecording:\(RecordingSessionSupport.outputLabel(for: outputMode))"
        ) else {
            return
        }
        pendingAutomaticDictionaryLearningTask?.cancel()
        guard !isSessionActive else {
            VoiceCoreLog.asr(
                "Begin recording ignored because a session is already active. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), activeOutput=\(RecordingSessionSupport.outputLabel(for: sessionOutputMode))"
            )
            return
        }
        releaseResidualRecordingResources(reason: "begin-recording")
        prepareLegacySettingsForSession(outputMode: outputMode)
        synchronizeRuntimeASRStateForSession(outputMode: outputMode)
        let startDecision = RecordingStartPlanner.resolve(selectedEngine: transcriptionEngine)
        let recordingEngine: TranscriptionEngine
        switch startDecision {
        case .start(let engine):
            recordingEngine = engine
        }
        guard preflightPermissionsForRecording(engine: recordingEngine) else {
            VoiceCoreLog.asr(
                "Begin recording blocked by preflight permissions. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), engine=\(recordingEngine.rawValue)"
            )
            return
        }

        cancelPendingFinishTasks()
        overlayState.isCompleting = false
        setEnhancingState(false)
        recordingStartedAt = Date()
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        transcriptionResultReceivedAt = nil
        firstLiveASRPartialReceivedAt = nil
        sessionFinalOutputDeliveredAt = nil
        sessionLLMExecutionTimings = []
        localVADObservedFramesInCurrentSession = false
        localVADObservedSpeechInCurrentSession = false
        didCommitSessionOutput = false
        isSessionCancellationRequested = false
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        pendingOutputReplacementTransaction = nil
        currentEndingSessionID = nil
        lastCompletedSessionEndSessionID = nil
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil
        sessionOutputDestinationContext = nil
        rewriteSessionHasSelectedSourceText = false
        resetSessionTranslationState()
        configureVoiceCoreNoteSessionRuntimeStateForNewRecording(
            mode: outputMode == .transcription ? transcriptionCaptureMode : .standard
        )
        configureTranscriptionCapturePipelineForCurrentSession()
        prewarmLLMForUpcomingSession(outputMode: outputMode)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let sessionTargetBundleID = RecordingSessionSupport.fallbackInjectBundleID(
            from: frontmostBundleID,
            ownBundleID: Bundle.main.bundleIdentifier
        )
        sessionTargetApplicationBundleID = sessionTargetBundleID
        sessionTargetApplicationPID = sessionTargetBundleID == nil ? nil : frontmostApplication?.processIdentifier
        let isContinuingRewriteConversation = outputMode == .rewrite && overlayState.isRewriteConversationActive
        if outputMode == .rewrite, !isContinuingRewriteConversation {
            rewriteSessionSelectedSourceText = selectedContentTextFromSystemSelection() ?? ""
        } else {
            rewriteSessionSelectedSourceText = ""
        }
        rewriteSessionHasSelectedSourceText = !rewriteSessionSelectedSourceText.isEmpty
        rewriteSessionHadWritableFocusedInput = isContinuingRewriteConversation
            ? false
            : (outputMode == .rewrite ? hasWritableFocusedTextInput() : false)
        rewriteSessionFallbackInjectBundleID = outputMode == .rewrite ? sessionTargetBundleID : nil
        resetVoiceEndCommandState()

        VoiceCoreLog.asr(
            "Recording started. output=\(RecordingSessionSupport.outputLabel(for: outputMode)), engine=\(recordingEngine.rawValue), pipeline=\(transcriptionCapturePipeline.rawValue)"
        )
        if outputMode == .rewrite {
            VoiceCoreLog.asr(
                "Rewrite focused input check at session start. hasWritableFocusedInput=\(rewriteSessionHadWritableFocusedInput)"
            )
            VoiceCoreLog.asr(
                "Rewrite fallback inject target at session start. frontmostBundleID=\(frontmostBundleID ?? "nil"), fallbackBundleID=\(rewriteSessionFallbackInjectBundleID ?? "nil")"
            )
        }

        applyPreferredInputDevice()
        if isContinuingRewriteConversation {
            overlayState.clearPendingConversationUserPrompt()
            overlayState.statusMessage = ""
            overlayState.sessionIconMode = .rewrite
            overlayState.isRewriteConversationTurnInProgress = true
            overlayState.answerTitle = ""
            overlayState.answerContent = ""
            overlayState.isStreamingAnswer = false
            overlayState.isRecording = false
            overlayState.isEnhancing = false
            overlayState.isRequesting = false
            overlayState.isCompleting = false
            overlayState.audioLevel = 0
            overlayState.transcribedText = ""
            overlayState.displayMode = .answer
        } else {
            overlayState.reset()
            overlayState.statusMessage = ""
            overlayState.presentRecording(iconMode: currentRecordingOverlayIconMode)
            overlayWindow.show(state: overlayState, position: overlayPosition)
        }
        if outputMode == .translation {
            prepareMicrophoneTranslationSessionState()
        }

        isSessionActive = true
        let shouldEnableCommonStopKey = outputMode == .translation ||
            outputMode == .rewrite ||
            transcriptionHotkeyStartBehavior == .tap ||
            transcriptionHotkeyStartBehavior == .doubleTap
        hotkeyManager.setCommonStopKeyEnabled(shouldEnableCommonStopKey)
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil

        if muteSystemAudioWhileRecording {
            let muteActivated = systemAudioMuteController.muteSystemAudioIfNeeded()
            VoiceCoreLog.info("System audio mute requested for recording start. activated=\(muteActivated)")
        }
        if interactionSoundsEnabled, outputMode != .transcription {
            interactionSoundPlayer.playStart()
        }

        startRecordingCapture(using: recordingEngine)
    }

    func endRecording() {
        guard isSessionActive else { return }
        guard recordingStoppedAt == nil else {
            VoiceCoreLog.hotkey("Recording stop ignored: session is already stopping.")
            return
        }
        let stoppingSessionID = activeRecordingSessionID
        VoiceCoreLog.asr("Recording stop requested.")

        hotkeyManager.setCommonStopKeyEnabled(false)
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
        prewarmLLMForPendingPostASRProcessing(outputMode: sessionOutputMode)
        overlayState.presentProcessing(iconMode: currentRecordingOverlayIconMode)
        voiceEndCommandState.lastDetectedCommand = false
        enhancementContextSnapshot = captureEnhancementContextSnapshot()
        stopActiveRecordingTranscriberAfterPendingVADFlush(sessionID: stoppingSessionID)
    }

    func cancelActiveRecordingSession() {
        guard isSessionActive else { return }
        VoiceCoreLog.asr("Recording cancelled by Escape key.")

        let cancelledSessionID = activeRecordingSessionID
        hotkeyManager.setCommonStopKeyEnabled(false)
        activeRecordingSessionID = UUID()
        invalidateActiveLLMRequest()
        pendingOutputReplacementTransaction = nil
        isSessionCancellationRequested = true
        didCommitSessionOutput = true
        sessionTargetApplicationPID = nil
        sessionTargetApplicationBundleID = nil
        sessionOutputDestinationContext = nil

        cancelSessionControlTasks()
        pendingSystemAudioMuteTask?.cancel()
        pendingSystemAudioMuteTask = nil
        recordingStoppedAt = Date()
        overlayState.isCompleting = false
        overlayState.statusMessage = ""
        setEnhancingState(false)
        resetVoiceEndCommandState()
        stopActiveRecordingTranscriber()

        VoiceCoreLog.asr("Cancelled session invalidated. sessionID=\(cancelledSessionID.uuidString)", verbose: true)
        executeSessionEndPipeline(for: cancelledSessionID, trigger: "cancel")
    }

    func finishSession(after delay: TimeInterval? = nil) {
        cancelSessionControlTasks()

        let resolvedDelay = delay ?? sessionFinishDelay
        let finishingSessionID = activeRecordingSessionID
        VoiceCoreLog.asr("Finish session scheduled. delayMs=\(Int(resolvedDelay * 1000)), displayMode=\(overlayState.displayMode), isRecording=\(overlayState.isRecording), isEnhancing=\(overlayState.isEnhancing), isRequesting=\(overlayState.isRequesting)", verbose: true)
        overlayState.isCompleting = resolvedDelay > 0
        if overlayState.displayMode != .answer {
            overlayState.isEnhancing = false
            overlayState.isRequesting = false
        }
        pendingSessionFinishTask = Task { [weak self] in
            guard let self else { return }

            if resolvedDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(resolvedDelay))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            guard self.activeRecordingSessionID == finishingSessionID else {
                VoiceCoreLog.asr(
                    "Finish session ignored because session ID changed before execution. scheduledSessionID=\(finishingSessionID.uuidString), currentSessionID=\(self.activeRecordingSessionID.uuidString)"
                )
                return
            }
            VoiceCoreLog.asr("Finish session executing now. displayMode=\(self.overlayState.displayMode)", verbose: true)
            self.executeSessionEndPipeline(for: finishingSessionID, trigger: "finish")
        }
    }
}
