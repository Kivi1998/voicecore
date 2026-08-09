// MeetingStartPlannerTests.swift
// Provides Meeting Start Planner Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

@MainActor
final class MeetingStartPlannerTests: XCTestCase {
    func testRemoteMeetingRequiresConfiguredProvider() {
        let blocked = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "")
        )
        XCTAssertEqual(blocked, .blocked(.remoteASRUnavailable))

        let allowed = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "token")
        )
        XCTAssertEqual(allowed, .start(.remote))
    }

    func testDoubaoMeetingUsesConfiguredRealtimeProvider() {
        let allowed = MeetingStartPlanner.resolve(
            selectedEngine: .remote,
            remoteASRProvider: .doubaoASR,
            remoteASRConfiguration: .init(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                endpoint: "",
                apiKey: "",
                appID: "app-id",
                accessToken: "token"
            )
        )
        XCTAssertEqual(allowed, .start(.remote))
    }

    func testDictationMeetingIsBlocked() {
        let decision = MeetingStartPlanner.resolve(
            selectedEngine: .dictation,
            remoteASRProvider: .openAIWhisper,
            remoteASRConfiguration: .init(providerID: RemoteASRProvider.openAIWhisper.rawValue, model: "whisper-1", endpoint: "", apiKey: "token")
        )

        XCTAssertEqual(decision, .blocked(.dictationUnsupported))
    }
}
