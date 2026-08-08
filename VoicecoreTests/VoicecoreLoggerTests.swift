// VoicecoreLoggerTests.swift
// Provides Voicecore Logger Tests for Voicecore test coverage.

import XCTest
@testable import Voicecore

final class VoicecoreLoggerTests: XCTestCase {
    func testVerboseLogDoesNotEvaluateMessageWhenVerboseLoggingIsDisabled() {
        let previousVerboseEnabled = VoicecoreLog.verboseEnabled
        VoicecoreLog.verboseEnabled = false
        defer {
            VoicecoreLog.verboseEnabled = previousVerboseEnabled
        }

        let logger = VoicecoreLogger(category: .app)
        var didEvaluateMessage = false

        logger.info({
            didEvaluateMessage = true
            return "expensive verbose message"
        }(), verbose: true)

        XCTAssertFalse(didEvaluateMessage)
    }
}
