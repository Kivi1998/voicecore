@testable import VoiceCoreDomain
import XCTest

final class DictationStatusTests: XCTestCase {
    /// 状态取值必须与 docs/DATA_MODEL.md §3.1 及 tasklist CORE-001 要求的 queued 一致。
    func testRawValuesMatchDataModel() {
        let expected: [DictationStatus: String] = [
            .created: "created",
            .queued: "queued",
            .recording: "recording",
            .audioSaved: "audio_saved",
            .transcribing: "transcribing",
            .transcriptionFailed: "transcription_failed",
            .transcribed: "transcribed",
            .rewriting: "rewriting",
            .rewriteFailed: "rewrite_failed",
            .ready: "ready",
            .injecting: "injecting",
            .injectionFailed: "injection_failed",
            .completed: "completed",
            .recordingFailed: "recording_failed",
            .cancelled: "cancelled"
        ]
        XCTAssertEqual(DictationStatus.allCases.count, expected.count)
        for (status, raw) in expected {
            XCTAssertEqual(status.rawValue, raw)
        }
    }

    func testFailureClassification() {
        XCTAssertTrue(DictationStatus.transcriptionFailed.isFailure)
        XCTAssertTrue(DictationStatus.rewriteFailed.isFailure)
        XCTAssertTrue(DictationStatus.injectionFailed.isFailure)
        XCTAssertTrue(DictationStatus.recordingFailed.isFailure)
        XCTAssertFalse(DictationStatus.completed.isFailure)
        XCTAssertFalse(DictationStatus.cancelled.isFailure)
        XCTAssertFalse(DictationStatus.recording.isFailure)
    }

    func testSettledClassification() {
        XCTAssertTrue(DictationStatus.completed.isSettled)
        XCTAssertTrue(DictationStatus.cancelled.isSettled)
        XCTAssertTrue(DictationStatus.transcriptionFailed.isSettled)
        XCTAssertFalse(DictationStatus.transcribing.isSettled)
        XCTAssertFalse(DictationStatus.queued.isSettled)
    }

    func testStageMapping() {
        XCTAssertEqual(DictationStatus.recording.stage, .recording)
        XCTAssertEqual(DictationStatus.audioSaved.stage, .recording)
        XCTAssertEqual(DictationStatus.transcribing.stage, .transcription)
        XCTAssertEqual(DictationStatus.transcriptionFailed.stage, .transcription)
        XCTAssertEqual(DictationStatus.rewriteFailed.stage, .rewrite)
        XCTAssertEqual(DictationStatus.ready.stage, .injection)
        XCTAssertEqual(DictationStatus.completed.stage, .injection)
    }
}
