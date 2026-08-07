import Foundation

/// 口述记录状态机状态。
///
/// 取值与 `docs/DATA_MODEL.md` §3.1 保持一致；`queued` 为
/// `KIMI_PROMPT.md` §2.1 与 `tasklist.md` CORE-001 额外要求的排队状态，
/// 表示录音或任务已建立、正在等待进入对应处理阶段。
///
/// 合法迁移规则由 CORE-002 状态机实现唯一拥有，本类型只做分类判断。
public enum DictationStatus: String, Codable, Sendable, CaseIterable {
    /// 记录已创建，尚未获得音频帧。
    case created
    /// 已排队，等待进入处理阶段（例如录音已保存、等待转录调度）。
    case queued
    /// 正在采集音频并持续写盘。
    case recording
    /// 录音文件已安全关闭且通过基本完整性检查。
    case audioSaved = "audio_saved"
    /// 正在调用语音识别服务。
    case transcribing
    /// 语音识别失败，可使用原录音重试。
    case transcriptionFailed = "transcription_failed"
    /// 原始转录已落库。
    case transcribed
    /// 正在调用文字改写服务。
    case rewriting
    /// 文字改写失败，可仅重新改写，不得重复上传音频。
    case rewriteFailed = "rewrite_failed"
    /// 最终文字已落库，等待自动输入。
    case ready
    /// 正在向当前输入框写入。
    case injecting
    /// 自动输入失败；最终文字仍可复制。
    case injectionFailed = "injection_failed"
    /// 全流程完成。
    case completed
    /// 录音阶段失败。
    case recordingFailed = "recording_failed"
    /// 用户主动取消；录音默认保留并允许删除。
    case cancelled

    /// 是否为某阶段失败状态（均可按能力恢复或重试）。
    public var isFailure: Bool {
        switch self {
        case .transcriptionFailed, .rewriteFailed, .injectionFailed, .recordingFailed:
            true
        default:
            false
        }
    }

    /// 是否为流水线的停滞终态（成功、取消或失败；失败可经用户重试再次进入流水线）。
    public var isSettled: Bool {
        switch self {
        case .completed, .cancelled, .transcriptionFailed, .rewriteFailed, .injectionFailed, .recordingFailed:
            true
        default:
            false
        }
    }

    /// 状态所属阶段，用于历史筛选与错误定位。
    public var stage: DictationStage {
        switch self {
        case .created, .queued, .recording, .audioSaved, .recordingFailed, .cancelled:
            .recording
        case .transcribing, .transcriptionFailed, .transcribed:
            .transcription
        case .rewriting, .rewriteFailed:
            .rewrite
        case .ready, .injecting, .injectionFailed, .completed:
            .injection
        }
    }
}

/// 口述流水线阶段。
public enum DictationStage: String, Codable, Sendable, CaseIterable {
    case recording
    case transcription
    case rewrite
    case injection
}
