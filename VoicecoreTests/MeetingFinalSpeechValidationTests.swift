import XCTest
@testable import Voicecore

final class MeetingFinalSpeechValidationTests: XCTestCase {
    func testOmniBatchBackendProcessesWholeAudioSilence() async throws {
        let backend = OmniOfflineVoiceActivityBackend(useCase: .meeting)

        let ranges: [ASROfflineSpeechRange]
        do {
            ranges = try await backend.speechRanges(
                samples: [Float](repeating: 0, count: 16_000),
                sampleRate: 16_000
            )
        } catch OmniVADError.modelNotFound(let filename) {
            throw XCTSkip("OmniVAD model resource '\(filename)' is not provisioned in this environment.")
        }

        XCTAssertTrue(ranges.isEmpty)
    }

    func testStandardPolicyDropsOnlySegmentsInsideEvaluatedSilence() {
        let speech = makeSegment(start: 1, end: 2, text: "speech")
        let silence = makeSegment(start: 3, end: 4, text: "hallucination")
        var evidence = MeetingFinalSpeechEvidence()
        evidence.record(
            source: .microphone,
            assetStartSeconds: 0,
            assetDurationSeconds: 5,
            speechRanges: [ASROfflineSpeechRange(startSeconds: 0.8, endSeconds: 2.2)]
        )

        let output = MeetingFinalSpeechValidator.validatedSegments(
            [speech, silence],
            evidence: evidence
        )

        XCTAssertEqual(output, [speech])
    }

    func testStandardPolicyPreservesSegmentWhenEvidenceIsUnavailable() {
        let segment = makeSegment(start: 1, end: 2)

        let output = MeetingFinalSpeechValidator.validatedSegments(
            [segment],
            evidence: nil
        )

        XCTAssertEqual(output, [segment])
    }

    func testStandardPolicyPreservesSegmentOutsideEvaluatedCoverage() {
        let segment = makeSegment(start: 8, end: 9)
        var evidence = MeetingFinalSpeechEvidence()
        evidence.record(
            source: .microphone,
            assetStartSeconds: 0,
            assetDurationSeconds: 5,
            speechRanges: []
        )

        let output = MeetingFinalSpeechValidator.validatedSegments(
            [segment],
            evidence: evidence
        )

        XCTAssertEqual(output, [segment])
    }

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        text: String = "text"
    ) -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(
            speaker: .me,
            audioSource: .microphone,
            startSeconds: start,
            endSeconds: end,
            text: text
        )
    }
}
