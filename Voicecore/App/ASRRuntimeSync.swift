// ASRRuntimeSync.swift
// Provides ASRRuntime Sync for app lifecycle and routing.

import Foundation

extension AppDelegate {
    func synchronizeRuntimeASRStateForSession(outputMode: SessionOutputMode) {
        synchronizeRuntimeASRState(for: asrSelectionID(for: outputMode))
    }

    func synchronizeRuntimeASRStateForMeeting() {
        synchronizeRuntimeASRState(for: meetingFeatureSettings.asrSelectionID)
    }

    private func asrSelectionID(for outputMode: SessionOutputMode) -> FeatureModelSelectionID {
        switch outputMode {
        case .transcription:
            return transcriptionFeatureSettings.asrSelectionID
        case .translation:
            return translationFeatureSettings.asrSelectionID
        case .rewrite:
            return rewriteFeatureSettings.asrSelectionID
        }
    }

    private func synchronizeRuntimeASRState(for selectionID: FeatureModelSelectionID) {
        // On-device MLX/Sherpa ONNX transcription has been removed, so there is no
        // runtime engine state left to synchronize for any selection.
    }
}
