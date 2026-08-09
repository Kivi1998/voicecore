// MeetingStartPlanner.swift
// Provides Meeting Start Planner for app lifecycle and routing.

import Foundation

enum MeetingStartBlockReason: Equatable {
    case dictationUnsupported
    case remoteASRUnavailable
    case remoteASRMeetingUnavailable(RemoteASRProvider)

    var userMessage: String {
        switch self {
        case .dictationUnsupported:
            return AppLocalization.localizedString("Meeting Notes currently supports Remote ASR. Direct Dictation is not available for meetings.")
        case .remoteASRUnavailable:
            return AppLocalization.localizedString("Remote ASR is not configured yet. Open Settings > Model to finish the provider setup.")
        case .remoteASRMeetingUnavailable(let provider):
            return RemoteASRMeetingConfiguration.startBlockedMessage(for: provider)
        }
    }

    var logDescription: String {
        switch self {
        case .dictationUnsupported:
            return "Meeting Notes does not support Direct Dictation."
        case .remoteASRUnavailable:
            return "Remote ASR provider configuration is incomplete."
        case .remoteASRMeetingUnavailable(let provider):
            return "Meeting ASR provider configuration is incomplete for \(provider.rawValue)."
        }
    }
}

enum MeetingStartDecision: Equatable {
    case start(TranscriptionEngine)
    case blocked(MeetingStartBlockReason)
}

enum MeetingStartPlanner {
    static func resolve(
        selectedEngine: TranscriptionEngine,
        remoteASRProvider: RemoteASRProvider,
        remoteASRConfiguration: RemoteProviderConfiguration
    ) -> MeetingStartDecision {
        switch selectedEngine {
        case .dictation:
            return .blocked(.dictationUnsupported)
        case .remote:
            guard remoteASRConfiguration.isConfigured else {
                return .blocked(.remoteASRUnavailable)
            }
            guard RemoteASRMeetingConfiguration.hasValidMeetingModel(
                provider: remoteASRProvider,
                configuration: remoteASRConfiguration
            ) else {
                return .blocked(.remoteASRMeetingUnavailable(remoteASRProvider))
            }
            return .start(.remote)
        case .mlxAudio, .sherpaOnnx:
            return .blocked(.dictationUnsupported)
        }
    }
}
