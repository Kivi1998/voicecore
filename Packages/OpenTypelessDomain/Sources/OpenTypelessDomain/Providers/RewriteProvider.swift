import Foundation

/// 文字改写能力声明。
public struct RewriteCapabilities: Codable, Sendable, Equatable {
    /// 支持系统提示词。
    public var supportsSystemPrompt: Bool
    /// 支持最大输出长度参数。
    public var supportsMaxOutputTokens: Bool
    /// 支持温度参数。
    public var supportsTemperature: Bool

    public init(
        supportsSystemPrompt: Bool = true,
        supportsMaxOutputTokens: Bool = true,
        supportsTemperature: Bool = true
    ) {
        self.supportsSystemPrompt = supportsSystemPrompt
        self.supportsMaxOutputTokens = supportsMaxOutputTokens
        self.supportsTemperature = supportsTemperature
    }
}

/// 文字改写请求。
public struct RewriteRequest: Sendable, Equatable {
    /// 语音识别原文；改写必须保留原意、专有名词、代码、数字和中英混合内容。
    public var originalText: String
    /// 词典词语，用于纠正专有名词。
    public var vocabularyTerms: [String]
    /// 界面语言（例如 `zh-Hans`），用于提示词组装。
    public var uiLanguage: String
    /// 用户可选附加指令；不得覆盖内置整理目标。
    public var userInstruction: String?
    /// 最大输出长度（token）。
    public var maxOutputTokens: Int
    /// 温度；nil 表示使用供应商默认。
    public var temperature: Double?
    /// 请求超时（秒）。
    public var timeoutSeconds: TimeInterval
    /// 仅用于本地日志关联。
    public var recordID: UUID
    public var attemptID: UUID

    public init(
        originalText: String,
        vocabularyTerms: [String] = [],
        uiLanguage: String = "zh-Hans",
        userInstruction: String? = nil,
        maxOutputTokens: Int = 2048,
        temperature: Double? = nil,
        timeoutSeconds: TimeInterval = 60,
        recordID: UUID,
        attemptID: UUID
    ) {
        self.originalText = originalText
        self.vocabularyTerms = vocabularyTerms
        self.uiLanguage = uiLanguage
        self.userInstruction = userInstruction
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.recordID = recordID
        self.attemptID = attemptID
    }
}

/// 改写完成原因。
public enum RewriteFinishReason: String, Codable, Sendable {
    case completed
    /// 达到最大输出长度被截断。
    case lengthLimited
    case unknown
}

/// 标准化文字改写结果。
public struct RewriteResult: Sendable, Equatable {
    /// 最终文字。
    public var finalText: String
    public var providerRequestID: String?
    /// 可选 token 用量（输入/输出）。
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var finishReason: RewriteFinishReason

    public init(
        finalText: String,
        providerRequestID: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        finishReason: RewriteFinishReason = .unknown
    ) {
        self.finalText = finalText
        self.providerRequestID = providerRequestID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.finishReason = finishReason
    }
}

/// 统一文字改写适配器接口。
///
/// OpenAI 兼容与 Anthropic 兼容适配器必须共用本接口。
/// 原始转录由上层保存；本接口只返回最终文字与标准元数据。
/// 空文本由上层短路处理（不发起请求），适配器收到空文本应返回
/// `configuration_invalid` 类错误而非发起无意义请求。
public protocol RewriteProvider: Sendable {
    var capabilities: RewriteCapabilities { get }

    /// 配置校验与连接测试（使用固定无隐私短文本）。
    func validate() async throws -> ValidationResult

    /// 执行改写。
    /// - Throws: `DictationError`（标准化错误类别）或 `CancellationError`。
    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult
}
