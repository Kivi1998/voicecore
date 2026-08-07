@testable import OpenTypelessDomain
import XCTest

/// 验证语音/改写契约可被测试替身实现，且模型类型行为符合规范（STT-001、LLM-001）。
final class ProviderContractTests: XCTestCase {
    struct FakeSpeechProvider: SpeechProvider {
        var capabilities: SpeechCapabilities {
            SpeechCapabilities(supportsFileUpload: true, supportsLanguageHint: true, supportsVocabularyPrompt: true)
        }

        func validate() async throws -> ValidationResult {
            .success(latencyMs: 120)
        }

        func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
            guard !request.vocabularyTerms.isEmpty else {
                throw DictationError(category: .configurationInvalid, userMessage: "缺少词典", isRetryable: false)
            }
            return SpeechResult(text: "你好，世界", detectedLanguage: "zh", providerRequestID: "req-1")
        }
    }

    struct FakeRewriteProvider: RewriteProvider {
        var capabilities: RewriteCapabilities {
            RewriteCapabilities()
        }

        func validate() async throws -> ValidationResult {
            .failed(
                DictationError(category: .authenticationFailed, userMessage: "鉴权失败", isRetryable: false),
                latencyMs: 80
            )
        }

        func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
            RewriteResult(finalText: request.originalText, providerRequestID: "rw-1", finishReason: .completed)
        }
    }

    func testSpeechContractUsable() async throws {
        let provider = FakeSpeechProvider()
        XCTAssertTrue(provider.capabilities.supportsFileUpload)
        let validation = try await provider.validate()
        XCTAssertEqual(validation.outcome, .success)

        let request = SpeechRequest(
            audioFile: URL(fileURLWithPath: "/tmp/a.m4a"),
            mimeType: "audio/mp4",
            durationMs: 1000,
            vocabularyTerms: ["世界"],
            recordID: UUID(),
            attemptID: UUID()
        )
        let result = try await provider.transcribe(request)
        XCTAssertEqual(result.text, "你好，世界")
    }

    func testSpeechErrorIsStandardized() async {
        let provider = FakeSpeechProvider()
        let request = SpeechRequest(
            audioFile: URL(fileURLWithPath: "/tmp/a.m4a"),
            mimeType: "audio/mp4",
            durationMs: 1000,
            recordID: UUID(),
            attemptID: UUID()
        )
        do {
            _ = try await provider.transcribe(request)
            XCTFail("应抛出 DictationError")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
    }

    func testRewriteContractUsable() async throws {
        let provider = FakeRewriteProvider()
        let validation = try await provider.validate()
        XCTAssertEqual(validation.outcome, .failed)
        XCTAssertEqual(validation.error?.category, .authenticationFailed)

        let request = RewriteRequest(originalText: "原始文字", recordID: UUID(), attemptID: UUID())
        let result = try await provider.rewrite(request)
        XCTAssertEqual(result.finalText, "原始文字")
        XCTAssertEqual(result.finishReason, .completed)
    }

    func testLanguageHintRawValues() {
        XCTAssertEqual(SpeechLanguageHint.automatic.rawValue, "auto")
        XCTAssertEqual(SpeechLanguageHint.chinese.rawValue, "zh")
        XCTAssertEqual(SpeechLanguageHint.english.rawValue, "en")
    }
}
