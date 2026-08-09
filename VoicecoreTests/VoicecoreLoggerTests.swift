// VoiceCoreLoggerTests.swift
// Provides VoiceCore Logger Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class VoiceCoreLoggerTests: XCTestCase {
    func testVerboseLogDoesNotEvaluateMessageWhenVerboseLoggingIsDisabled() {
        let previousVerboseEnabled = VoiceCoreLog.verboseEnabled
        VoiceCoreLog.verboseEnabled = false
        defer {
            VoiceCoreLog.verboseEnabled = previousVerboseEnabled
        }

        let logger = VoiceCoreLogger(category: .app)
        var didEvaluateMessage = false

        logger.info({
            didEvaluateMessage = true
            return "expensive verbose message"
        }(), verbose: true)

        XCTAssertFalse(didEvaluateMessage)
    }
}
