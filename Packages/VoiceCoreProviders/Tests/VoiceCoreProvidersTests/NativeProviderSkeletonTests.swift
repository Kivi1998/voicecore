import Foundation
import VoiceCoreDomain
@testable import VoiceCoreProviders
import XCTest

/// 原生适配器骨架测试（STT-005）：接口完整、错误明确、不误导。
final class NativeProviderSkeletonTests: XCTestCase {
    func testQwenSkeletonThrowsClearUnsupportedError() async throws {
        let provider = QwenSpeechProviderSkeleton()
        XCTAssertTrue(provider.capabilities.supportsStreaming)
        XCTAssertFalse(provider.capabilities.supportsFileUpload)

        do {
            _ = try await provider.transcribe(SpeechRequest(
                audioFile: URL(fileURLWithPath: "/tmp/test.m4a"),
                mimeType: "audio/mp4",
                durationMs: 1000,
                recordID: UUID(),
                attemptID: UUID()
            ))
            XCTFail("骨架应抛出明确的暂不支持错误")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
            XCTAssertFalse(error.isRetryable)
            XCTAssertTrue(error.userMessage.contains("OpenAI 兼容"))
        }

        let validation = try await provider.validate()
        XCTAssertEqual(validation.outcome, .failed)
        XCTAssertEqual(validation.error?.category, .configurationInvalid)
    }
}
