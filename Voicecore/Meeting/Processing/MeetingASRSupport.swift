// MeetingASRSupport.swift
// Provides Meeting ASRSupport for meeting transcript processing.

import Foundation

enum MeetingASRResolvedMode: Equatable, Sendable {
    case chunk(profile: MeetingChunkingProfile)
    case liveRemote(provider: RemoteASRProvider)

    var chunkingProfile: MeetingChunkingProfile {
        switch self {
        case .chunk(let profile):
            return profile
        case .liveRemote:
            return .realtime
        }
    }

    var usesLiveSessions: Bool {
        switch self {
        case .liveRemote:
            return true
        case .chunk:
            return false
        }
    }

    /// Always false now that on-device MLX transcription has been removed; kept so the
    /// (now permanently unreachable) local-live audio-gating paths still type-check.
    var usesLocalVoiceActivityGate: Bool { false }
}

struct MeetingASREngineContext: Equatable {
    let engine: TranscriptionEngine
    let historyModelDescription: String
    let resolvedMode: MeetingASRResolvedMode
    let needsModelInitialization: Bool

    var chunkingProfile: MeetingChunkingProfile {
        resolvedMode.chunkingProfile
    }

    func resolvingChunkingMode(_ mode: MeetingChunkingMode) -> MeetingASREngineContext {
        guard case .chunk(let automaticProfile) = resolvedMode else {
            return self
        }
        return MeetingASREngineContext(
            engine: engine,
            historyModelDescription: historyModelDescription,
            resolvedMode: .chunk(profile: mode.resolvedProfile(automaticProfile: automaticProfile)),
            needsModelInitialization: needsModelInitialization
        )
    }
}

enum MeetingASRSupport {
    static func resolveContext(
        remoteProvider: RemoteASRProvider,
        remoteConfiguration: RemoteProviderConfiguration
    ) -> MeetingASREngineContext {
        let resolvedMode = resolveRemoteMode(
            provider: remoteProvider,
            configuration: remoteConfiguration
        )
        let modelConfiguration = resolvedMode.usesLiveSessions
            ? remoteConfiguration
            : RemoteASRMeetingConfiguration.resolvedMeetingConfiguration(
                provider: remoteProvider,
                configuration: remoteConfiguration
            )
        let model = modelConfiguration.hasUsableModel ? modelConfiguration.model : remoteProvider.suggestedModel
        return MeetingASREngineContext(
            engine: .remote,
            historyModelDescription: "\(remoteProvider.title) (\(model))",
            resolvedMode: resolvedMode,
            needsModelInitialization: false
        )
    }

    static func resolveRemoteMode(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> MeetingASRResolvedMode {
        if RemoteASRRealtimeSupport.usesRealtimeMeetingProfile(
            provider: provider,
            configuration: configuration
        ) {
            return .liveRemote(provider: provider)
        }

        switch provider {
        case .doubaoASR:
            return .chunk(profile: .quality)
        case .aliyunBailianASR:
            return .chunk(profile: .quality)
        case .openAIWhisper:
            return .chunk(profile: configuration.openAIChunkPseudoRealtimeEnabled ? .realtime : .quality)
        case .glmASR, .stepFunASR, .xiaomiMiMoASR:
            return .chunk(profile: .quality)
        }
    }
}

extension RemoteASRRealtimeSupport {
    static func usesRealtimeMeetingProfile(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> Bool {
        switch provider {
        case .openAIWhisper:
            return false
        case .doubaoASR:
            return true
        case .glmASR:
            return false
        case .aliyunBailianASR:
            return isAliyunRealtimeModel(configuration.model)
        case .stepFunASR:
            return false
        case .xiaomiMiMoASR:
            return false
        }
    }
}
