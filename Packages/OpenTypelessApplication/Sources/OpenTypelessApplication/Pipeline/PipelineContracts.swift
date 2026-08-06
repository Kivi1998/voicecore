import Foundation
import OpenTypelessDomain

/// 流水线运行选项（由应用设置在会话开始时快照）。
public struct PipelineOptions: Sendable, Equatable {
    /// 是否启用文字改写；关闭时原始转录直接成为最终文字。
    public var rewriteEnabled: Bool
    /// 是否自动写入当前输入框。
    public var autoInsert: Bool
    /// 自动输入后是否恢复原剪贴板。
    public var restoreClipboard: Bool
    /// 语言提示。
    public var languageHint: SpeechLanguageHint

    public init(
        rewriteEnabled: Bool = true,
        autoInsert: Bool = true,
        restoreClipboard: Bool = true,
        languageHint: SpeechLanguageHint = .automatic
    ) {
        self.rewriteEnabled = rewriteEnabled
        self.autoInsert = autoInsert
        self.restoreClipboard = restoreClipboard
        self.languageHint = languageHint
    }
}

/// 流水线选项提供者（应用层从设置仓储实现）。
public protocol PipelineOptionsProvider: Sendable {
    func currentOptions() async throws -> PipelineOptions
}

/// 提供商工厂（组合根实现：从配置仓储读取默认配置与受限秘密，
/// 构造对应协议的适配器）。
public protocol ProviderFactory: Sendable {
    /// 当前启用的语音识别适配器与脱敏快照；未配置返回 nil。
    func makeSpeechProvider() async throws -> (any SpeechProvider, ProviderProfileSnapshot)?

    /// 当前启用的改写适配器与脱敏快照；关闭改写或未配置返回 nil。
    func makeRewriteProvider() async throws -> (any RewriteProvider, ProviderProfileSnapshot)?

    /// 当前词典词语（语音提示与改写纠错上下文）。
    func vocabularyTerms() async throws -> [String]
}

/// 口述会话事件（不含密钥与长文本；长文字按需经仓储查询）。
public enum DictationSessionEvent: Sendable, Equatable {
    /// 记录状态变化。
    case statusChanged(recordID: UUID, status: DictationStatus)
    /// 录音输入电平（0～1）。
    case levelUpdated(Float)
    /// 会话结束（成功、失败或取消后的最终状态）。
    case sessionFinished(recordID: UUID, status: DictationStatus)
}
