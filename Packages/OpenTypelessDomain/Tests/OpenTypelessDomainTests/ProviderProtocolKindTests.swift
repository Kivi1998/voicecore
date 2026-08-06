import XCTest

@testable import OpenTypelessDomain

final class ProviderProtocolKindTests: XCTestCase {
    /// 协议取值必须与 docs/DATA_MODEL.md §3.3 一一对应。
    func testRawValuesMatchDataModel() {
        XCTAssertEqual(ProviderProtocolKind.openAIAudioTranscription.rawValue, "openai_audio_transcription")
        XCTAssertEqual(ProviderProtocolKind.qwenNative.rawValue, "qwen_native")
        XCTAssertEqual(ProviderProtocolKind.doubaoNative.rawValue, "doubao_native")
        XCTAssertEqual(ProviderProtocolKind.openAIChat.rawValue, "openai_chat")
        XCTAssertEqual(ProviderProtocolKind.anthropicMessages.rawValue, "anthropic_messages")
    }

    func testPurposeMapping() {
        XCTAssertEqual(ProviderProtocolKind.openAIAudioTranscription.purpose, .speech)
        XCTAssertEqual(ProviderProtocolKind.qwenNative.purpose, .speech)
        XCTAssertEqual(ProviderProtocolKind.doubaoNative.purpose, .speech)
        XCTAssertEqual(ProviderProtocolKind.openAIChat.purpose, .rewrite)
        XCTAssertEqual(ProviderProtocolKind.anthropicMessages.purpose, .rewrite)
    }

    func testV1Availability() {
        XCTAssertTrue(ProviderProtocolKind.openAIAudioTranscription.isImplementedInV1)
        XCTAssertTrue(ProviderProtocolKind.openAIChat.isImplementedInV1)
        XCTAssertTrue(ProviderProtocolKind.anthropicMessages.isImplementedInV1)
        // 未实现的原生协议不得在界面显示为可用。
        XCTAssertFalse(ProviderProtocolKind.qwenNative.isImplementedInV1)
        XCTAssertFalse(ProviderProtocolKind.doubaoNative.isImplementedInV1)
    }
}
