@testable import VoiceCoreDomain
import XCTest

final class DictionaryTermTests: XCTestCase {
    func testNormalizationTrimsAndLowercases() {
        let term = DictionaryTerm(id: UUID(), term: "  OpenAI  ", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(term.term, "OpenAI")
        XCTAssertEqual(term.normalizedTerm, "openai")
    }

    func testValidationRejectsEmpty() {
        XCTAssertNotNil(DictionaryTerm.validationError(for: "   "))
        XCTAssertNotNil(DictionaryTerm.validationError(for: ""))
    }

    func testValidationRejectsTooLong() {
        let long = String(repeating: "字", count: DictionaryTerm.maxTermLength + 1)
        XCTAssertNotNil(DictionaryTerm.validationError(for: long))
    }

    func testValidationAcceptsNormalTerm() {
        XCTAssertNil(DictionaryTerm.validationError(for: "通义千问"))
    }
}

final class DictationRecordCodableTests: XCTestCase {
    func testRecordRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = ProviderProfileSnapshot(
            profileID: UUID(),
            name: "默认语音",
            protocolKind: .openAIAudioTranscription,
            baseURL: "https://api.example.com",
            modelName: "whisper-1"
        )
        let record = DictationRecord(
            id: UUID(),
            status: .completed,
            startedAt: now,
            stoppedAt: now.addingTimeInterval(3),
            completedAt: now.addingTimeInterval(8),
            durationMs: 3000,
            audioRelativePath: "2026/08/06/\(UUID().uuidString).m4a",
            audioMimeType: "audio/mp4",
            audioSizeBytes: 48000,
            rawTranscript: "你好 world",
            finalText: "你好，world。",
            countUnits: 4,
            speechSnapshot: snapshot,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DictationRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testAttemptRoundTrip() throws {
        let attempt = RecordAttempt(
            id: UUID(),
            recordID: UUID(),
            stage: .rewrite,
            attemptNumber: 2,
            providerKind: .anthropicMessages,
            modelName: "claude-sonnet-4-5",
            startedAt: Date(),
            success: false,
            httpStatus: 429,
            errorCategory: .rateLimited,
            errorMessage: "服务限流，请稍后重试"
        )
        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(RecordAttempt.self, from: data)
        XCTAssertEqual(decoded, attempt)
    }
}
