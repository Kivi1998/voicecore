import Foundation

/// 语言提示（首版允许自动、中、英）。
public enum SpeechLanguageHint: String, Codable, Sendable, CaseIterable {
    case automatic = "auto"
    case chinese = "zh"
    case english = "en"
}

/// 语音识别能力声明。
///
/// 业务层只能根据能力调用适配器，不得根据厂商名称分支。
public struct SpeechCapabilities: Codable, Sendable, Equatable {
    /// 支持文件上传转录（首版必需）。
    public var supportsFileUpload: Bool
    /// 支持实时流式音频（预留扩展）。
    public var supportsStreaming: Bool
    /// 支持语言提示。
    public var supportsLanguageHint: Bool
    /// 支持提示词/热词（词典注入）。
    public var supportsVocabularyPrompt: Bool
    /// 支持时间戳片段。
    public var supportsTimestamps: Bool

    public init(
        supportsFileUpload: Bool,
        supportsStreaming: Bool = false,
        supportsLanguageHint: Bool = false,
        supportsVocabularyPrompt: Bool = false,
        supportsTimestamps: Bool = false
    ) {
        self.supportsFileUpload = supportsFileUpload
        self.supportsStreaming = supportsStreaming
        self.supportsLanguageHint = supportsLanguageHint
        self.supportsVocabularyPrompt = supportsVocabularyPrompt
        self.supportsTimestamps = supportsTimestamps
    }
}

/// 语音识别请求。
///
/// 音频在发起本请求前必须已成为可独立播放的本地文件。
public struct SpeechRequest: Sendable, Equatable {
    /// 本地音频文件（由上层通过 PathService 解析得到）。
    public var audioFile: URL
    public var mimeType: String
    public var durationMs: Int64
    /// 可选语言提示。
    public var languageHint: SpeechLanguageHint
    /// 词典词语（适配器按能力决定是否注入，长度受限）。
    public var vocabularyTerms: [String]
    /// 请求超时（秒）；长音频允许更长总超时。
    public var timeoutSeconds: TimeInterval
    /// 仅用于本地日志关联的记录与尝试标识。
    public var recordID: UUID
    public var attemptID: UUID

    public init(
        audioFile: URL,
        mimeType: String,
        durationMs: Int64,
        languageHint: SpeechLanguageHint = .automatic,
        vocabularyTerms: [String] = [],
        timeoutSeconds: TimeInterval = 60,
        recordID: UUID,
        attemptID: UUID
    ) {
        self.audioFile = audioFile
        self.mimeType = mimeType
        self.durationMs = durationMs
        self.languageHint = languageHint
        self.vocabularyTerms = vocabularyTerms
        self.timeoutSeconds = timeoutSeconds
        self.recordID = recordID
        self.attemptID = attemptID
    }
}

/// 标准化语音识别结果。
///
/// 供应商私有响应结构不得传播到领域层。
public struct SpeechResult: Sendable, Equatable {
    /// 原始转录文字。
    public var text: String
    /// 供应商返回或推断的识别语言。
    public var detectedLanguage: String?
    /// 供应商请求标识。
    public var providerRequestID: String?
    /// 供应商报告的音频时长（毫秒）。
    public var reportedDurationMs: Int64?

    public init(
        text: String,
        detectedLanguage: String? = nil,
        providerRequestID: String? = nil,
        reportedDurationMs: Int64? = nil
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.providerRequestID = providerRequestID
        self.reportedDurationMs = reportedDurationMs
    }
}
