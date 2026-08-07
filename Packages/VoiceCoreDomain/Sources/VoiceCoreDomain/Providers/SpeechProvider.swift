import Foundation

/// 配置校验 / 连接测试结果。
///
/// 连接测试是用户显式操作，不得产生历史记录，不得记录密钥和完整响应正文。
public struct ValidationResult: Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        case success
        case failed
    }

    public var outcome: Outcome
    /// 测试耗时（毫秒），用于设置页反馈。
    public var latencyMs: Int64
    /// 失败时的标准化错误（已脱敏、用户可理解）。
    public var error: DictationError?

    public init(outcome: Outcome, latencyMs: Int64, error: DictationError? = nil) {
        self.outcome = outcome
        self.latencyMs = latencyMs
        self.error = error
    }

    public static func success(latencyMs: Int64) -> ValidationResult {
        ValidationResult(outcome: .success, latencyMs: latencyMs)
    }

    public static func failed(_ error: DictationError, latencyMs: Int64) -> ValidationResult {
        ValidationResult(outcome: .failed, latencyMs: latencyMs, error: error)
    }
}

/// 统一语音识别适配器接口。
///
/// 实现位于 VoiceCoreProviders；首版完整实现 OpenAI 兼容音频转录，
/// 千问、豆包原生协议通过新增适配器接入，不得修改录音、历史和统计主流程。
///
/// 取消语义：Swift `Task` 取消必须传播到对应网络任务；
/// 适配器把 `CancellationError` 作为取消结果，而不是供应商故障。
public protocol SpeechProvider: Sendable {
    /// 能力声明；业务层只能依据能力调用。
    var capabilities: SpeechCapabilities { get }

    /// 配置校验与连接测试（显式操作；语音配置使用应用自带的短小无敏感测试音频）。
    func validate() async throws -> ValidationResult

    /// 文件转录。
    /// - Throws: `DictationError`（标准化错误类别）或 `CancellationError`。
    func transcribe(_ request: SpeechRequest) async throws -> SpeechResult
}
