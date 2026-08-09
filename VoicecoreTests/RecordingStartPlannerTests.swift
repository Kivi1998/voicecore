// RecordingStartPlannerTests.swift
// Provides Recording Start Planner Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class RecordingStartPlannerTests: XCTestCase {
    func testResolveAlwaysStartsWithTheSelectedEngine() {
        XCTAssertEqual(RecordingStartPlanner.resolve(selectedEngine: .remote), .start(.remote))
        XCTAssertEqual(RecordingStartPlanner.resolve(selectedEngine: .dictation), .start(.dictation))
    }
}
