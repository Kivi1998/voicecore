// TranscriptionHistoryStatusTests.swift
// Provides Transcription History Status Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

@MainActor
final class TranscriptionHistoryStatusTests: XCTestCase {
    private func makeEntry(
        text: String = "Hello world",
        status: TranscriptionHistoryStatus = .completed,
        failureReason: String? = nil
    ) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: UUID(),
            text: text,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            transcriptionEngine: "Doubao",
            transcriptionModel: "doubao-flash",
            enhancementMode: "Off",
            enhancementModel: "None",
            kind: .normal,
            isTranslation: false,
            audioDurationSeconds: 3,
            transcriptionProcessingDurationSeconds: 1,
            llmDurationSeconds: nil,
            focusedAppName: nil,
            focusedAppBundleID: nil,
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            audioRelativePath: "transcription/sample.wav",
            whisperWordTimings: nil,
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: [],
            status: status,
            failureReason: failureReason
        )
    }

    /// Legacy entryJSON blobs persisted before the `status` field existed have no `status` key.
    /// They must still decode successfully and resolve to `.completed`, not crash or default to
    /// a failed state.
    func testDecodingLegacyEntryWithoutStatusKeyResolvesToCompleted() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "text": "Old entry from before this field existed",
            "createdAt": Date(timeIntervalSinceReferenceDate: 200).timeIntervalSince1970,
            "transcriptionEngine": "MLX Whisper",
            "transcriptionModel": "whisper-base-mlx",
            "enhancementMode": "Off",
            "enhancementModel": "None",
            "kind": "normal",
            "isTranslation": false,
            "dictionaryHitTerms": [],
            "dictionaryCorrectedTerms": [],
            "dictionarySuggestedTerms": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let entry = try decoder.decode(TranscriptionHistoryEntry.self, from: data)

        XCTAssertNil(entry.status)
        XCTAssertNil(entry.failureReason)
        XCTAssertEqual(entry.resolvedStatus, .completed)
        XCTAssertFalse(entry.resolvedStatus.isFailure)
    }

    func testFailedStatusRoundTripsThroughEncodeDecode() throws {
        let entry = makeEntry(text: "", status: .asrFailed, failureReason: "TLS connection failed")

        let data = try JSONEncoder().encode(entry)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranscriptionHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.resolvedStatus, .asrFailed)
        XCTAssertTrue(decoded.resolvedStatus.isFailure)
        XCTAssertEqual(decoded.text, "")
        XCTAssertEqual(decoded.failureReason, "TLS connection failed")
    }

    /// Regression test: `copy()` must preserve the entry's current status when a caller updates
    /// an unrelated field (e.g. dictionary correction) without explicitly passing `status`.
    /// This previously silently reset a failed entry's status back to `.completed` because the
    /// underlying `TranscriptionHistoryEntry(status:)` parameter defaulted to `nil`.
    func testCopyingEntryForUnrelatedFieldPreservesFailedStatus() {
        let failedEntry = makeEntry(
            text: "",
            status: .asrFailed,
            failureReason: "Network timeout"
        )

        let updated = failedEntry.updatingDictionaryCorrectedTerms(["term"])

        XCTAssertEqual(updated.resolvedStatus, .asrFailed)
        XCTAssertEqual(updated.dictionaryCorrectedTerms, ["term"])
        XCTAssertEqual(updated.failureReason, "Network timeout")
    }

    func testUpdatingStatusPreservesEveryOtherField() {
        let failedEntry = makeEntry(text: "", status: .asrFailed)

        let updated = failedEntry.updatingStatus(.completed)

        XCTAssertEqual(updated.resolvedStatus, .completed)
        XCTAssertEqual(updated.id, failedEntry.id)
        XCTAssertEqual(updated.audioRelativePath, failedEntry.audioRelativePath)
        XCTAssertEqual(updated.text, failedEntry.text)
        XCTAssertNil(updated.failureReason)
    }

    /// `updatingTranscriptionEntry` (used on a successful retry) must default to `.completed`
    /// even though the entry being updated started out failed.
    func testUpdatingTranscriptionEntryDefaultsToCompletedStatus() {
        let failedEntry = makeEntry(text: "", status: .asrFailed)

        let updated = failedEntry.updatingTranscriptionEntry(
            text: "Recovered transcription",
            createdAt: failedEntry.createdAt,
            audioDurationSeconds: failedEntry.audioDurationSeconds,
            transcriptionProcessingDurationSeconds: failedEntry.transcriptionProcessingDurationSeconds,
            llmDurationSeconds: 0.5,
            whisperWordTimings: nil,
            senseVoiceMetadata: nil,
            transcriptionChatMessages: [],
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionaryCorrectionSnapshots: [],
            dictionarySuggestedTerms: []
        )

        XCTAssertEqual(updated.resolvedStatus, .completed)
        XCTAssertEqual(updated.text, "Recovered transcription")
        XCTAssertNil(updated.failureReason)
    }

    func testStatusRawValueRoundTrip() {
        XCTAssertEqual(TranscriptionHistoryStatus(rawValue: "completed"), .completed)
        XCTAssertEqual(TranscriptionHistoryStatus(rawValue: "asrFailed"), .asrFailed)
        XCTAssertEqual(TranscriptionHistoryStatus(rawValue: "enhancementFailed"), .enhancementFailed)
        XCTAssertNil(TranscriptionHistoryStatus(rawValue: "unknownValue"))

        XCTAssertFalse(TranscriptionHistoryStatus.completed.isFailure)
        XCTAssertTrue(TranscriptionHistoryStatus.asrFailed.isFailure)
        XCTAssertTrue(TranscriptionHistoryStatus.enhancementFailed.isFailure)
    }
}
