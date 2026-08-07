import Foundation

/// 口述状态机。
///
/// 合法迁移表的唯一权威（`docs/ARCHITECTURE.md` §5）。
/// 仅允许预定义转移；每次状态变化与关联字段更新必须处于同一数据库
/// 事务中（由仓储层保证）。状态机只做合法性校验，不持有任何状态。
public enum DictationStateMachine {
    /// 合法迁移表。
    ///
    /// 包含三类转移：
    /// - 流水线主路径：created → recording → audioSaved → transcribing
    ///   → transcribed → rewriting → ready → injecting → completed；
    /// - 各阶段失败与重试：转录失败可重转录，改写失败可仅重写或采用原文，
    ///   输入失败可再次输入；
    /// - 启动恢复专用：created/recording/queued → audioSaved/recordingFailed、
    ///   transcribed → rewriteFailed、ready → injectionFailed
    ///   （ARCHITECTURE §5.1，恢复器不得自动向其他应用输入文字）。
    private static let legalTransitions: [DictationStatus: Set<DictationStatus>] = [
        .created: [.queued, .recording, .cancelled, .audioSaved, .recordingFailed],
        .queued: [.recording, .transcribing, .cancelled, .audioSaved, .recordingFailed],
        .recording: [.audioSaved, .recordingFailed, .cancelled],
        .audioSaved: [.queued, .transcribing],
        .transcribing: [.transcribed, .transcriptionFailed],
        .transcriptionFailed: [.transcribing],
        .transcribed: [.rewriting, .ready, .rewriteFailed],
        .rewriting: [.ready, .rewriteFailed],
        // 改写失败：可仅重新改写，或采用原始文字作为最终文字进入待输入。
        .rewriteFailed: [.rewriting, .ready],
        .ready: [.injecting, .injectionFailed, .completed],
        .injecting: [.completed, .injectionFailed],
        .injectionFailed: [.injecting],
        .recordingFailed: [],
        .completed: [],
        .cancelled: []
    ]

    /// 判断迁移是否合法。
    public static func canTransition(from source: DictationStatus, to target: DictationStatus) -> Bool {
        legalTransitions[source]?.contains(target) ?? false
    }

    /// 校验迁移；非法迁移抛出错误。
    /// - Throws: `DictationError`（`configurationInvalid` 类别）。
    public static func validateTransition(from source: DictationStatus, to target: DictationStatus) throws {
        guard canTransition(from: source, to: target) else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "非法状态迁移：\(source.rawValue) → \(target.rawValue)",
                isRetryable: false
            )
        }
    }

    /// 指定状态的全部合法后继。
    public static func legalTargets(from source: DictationStatus) -> Set<DictationStatus> {
        legalTransitions[source] ?? []
    }

    /// 终态（无合法后继）。
    public static func isTerminal(_ status: DictationStatus) -> Bool {
        legalTargets(from: status).isEmpty
    }
}
