import Foundation

/// 提供商配置用途。
public enum ProviderPurpose: String, Codable, Sendable, CaseIterable {
    /// 语音识别。
    case speech
    /// 文字改写。
    case rewrite
}

/// 提供商协议类型。
///
/// 取值与 `docs/DATA_MODEL.md` §3.3 一一对应。
/// `qwenNative` 为预留扩展值；`doubaoNative` 已实现录音文件极速版协议。
public enum ProviderProtocolKind: String, Codable, Sendable, CaseIterable {
    case openAIAudioTranscription = "openai_audio_transcription"
    case qwenNative = "qwen_native"
    case doubaoNative = "doubao_native"
    case openAIChat = "openai_chat"
    case anthropicMessages = "anthropic_messages"

    /// 该协议适用于的用途。
    public var purpose: ProviderPurpose {
        switch self {
        case .openAIAudioTranscription, .qwenNative, .doubaoNative:
            .speech
        case .openAIChat, .anthropicMessages:
            .rewrite
        }
    }

    /// 第一版是否已完整实现并可被用户选用。
    public var isImplementedInV1: Bool {
        switch self {
        case .openAIAudioTranscription, .doubaoNative, .openAIChat, .anthropicMessages:
            true
        case .qwenNative:
            false
        }
    }
}
