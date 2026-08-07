import Foundation
import OpenTypelessDomain

/// 千问原生语音识别适配器骨架（STT-005）。
///
/// 首版不实现原生调用：千问经 OpenAI 兼容配置即可使用
/// （`docs/PROVIDER_PROTOCOLS.md` §4）。本骨架实现完整 `SpeechProvider`
/// 接口，让组合根可以提前登记、设置页可以安全展示说明；
/// 真正的原生（实时 WebSocket / 专有热词）实现按
/// `docs/PROVIDER_EXTENSION.md` 清单替换本类型，不得修改流水线。
public struct QwenSpeechProviderSkeleton: SpeechProvider {
    public let capabilities: SpeechCapabilities

    public init() {
        capabilities = SpeechCapabilities(
            supportsFileUpload: false,
            supportsStreaming: true,
            supportsLanguageHint: true,
            supportsVocabularyPrompt: true
        )
    }

    public func validate() async throws -> ValidationResult {
        .failed(Self.unsupportedError, latencyMs: 0)
    }

    public func transcribe(_: SpeechRequest) async throws -> SpeechResult {
        throw Self.unsupportedError
    }

    static var unsupportedError: DictationError {
        DictationError(
            category: .configurationInvalid,
            userMessage: "千问原生协议将在后续版本提供，当前请使用 OpenAI 兼容方式配置千问",
            isRetryable: false
        )
    }
}

/// 豆包原生语音识别适配器骨架（STT-005）。
///
/// 豆包需要火山引擎专有鉴权与 WebSocket 数据帧
/// （`docs/PROVIDER_PROTOCOLS.md` §5），首版不实现原生调用。
public struct DoubaoSpeechProviderSkeleton: SpeechProvider {
    public let capabilities: SpeechCapabilities

    public init() {
        capabilities = SpeechCapabilities(
            supportsFileUpload: false,
            supportsStreaming: true,
            supportsLanguageHint: true,
            supportsVocabularyPrompt: true
        )
    }

    public func validate() async throws -> ValidationResult {
        .failed(Self.unsupportedError, latencyMs: 0)
    }

    public func transcribe(_: SpeechRequest) async throws -> SpeechResult {
        throw Self.unsupportedError
    }

    static var unsupportedError: DictationError {
        DictationError(
            category: .configurationInvalid,
            userMessage: "豆包原生协议将在后续版本提供，当前版本暂不可用",
            isRetryable: false
        )
    }
}
