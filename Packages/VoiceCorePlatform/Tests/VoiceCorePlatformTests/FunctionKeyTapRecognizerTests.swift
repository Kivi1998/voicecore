@testable import VoiceCorePlatform
import XCTest

final class FunctionKeyTapRecognizerTests: XCTestCase {
    func testSinglePressAndReleaseTriggersExactlyOnce() {
        var recognizer = FunctionKeyTapRecognizer()

        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        XCTAssertTrue(recognizer.handleFunctionFlag(isDown: false))
        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: false))
    }

    func testRepeatedDownEventsDoNotTriggerUntilRelease() {
        var recognizer = FunctionKeyTapRecognizer()

        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        XCTAssertTrue(recognizer.handleFunctionFlag(isDown: false))
    }

    func testCombinationInputSuppressesFunctionKeyTap() {
        var recognizer = FunctionKeyTapRecognizer()

        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        recognizer.noteCombinationInput()
        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: false))
    }

    func testCombinationStateDoesNotLeakIntoNextTap() {
        var recognizer = FunctionKeyTapRecognizer()

        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        recognizer.noteCombinationInput()
        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: false))
        XCTAssertFalse(recognizer.handleFunctionFlag(isDown: true))
        XCTAssertTrue(recognizer.handleFunctionFlag(isDown: false))
    }
}
