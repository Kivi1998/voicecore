import Foundation
import OpenTypelessDomain

/// 启动恢复报告（供诊断日志与界面提示使用，不含敏感内容）。
public struct RecoveryReport: Sendable, Equatable {
    /// 扫描到的未停滞记录数。
    public var scannedCount = 0
    /// 录音文件有效，恢复到待转录的记录。
    public var restoredToAudioSaved: [UUID] = []
    /// 录音文件缺失或损坏，标记录音失败的记录。
    public var markedRecordingFailed: [UUID] = []
    /// 转录中断，标记转录失败的记录。
    public var markedTranscriptionFailed: [UUID] = []
    /// 改写中断，标记改写失败的记录。
    public var markedRewriteFailed: [UUID] = []
    /// 输入中断，标记输入失败的记录（不自动重新输入）。
    public var markedInjectionFailed: [UUID] = []
    /// 收养半成品（.partial）恢复为正式录音的数量。
    public var adoptedPartialCount = 0

    public init() {}

    /// 本次是否有任何恢复动作。
    public var hasChanges: Bool {
        !(restoredToAudioSaved.isEmpty
            && markedRecordingFailed.isEmpty
            && markedTranscriptionFailed.isEmpty
            && markedRewriteFailed.isEmpty
            && markedInjectionFailed.isEmpty)
    }
}

/// 启动恢复能力协议（应用组合根在启动时调用一次）。
public protocol StartupRecovering: Sendable {
    /// 扫描未停滞记录并按恢复规则落库；幂等，不创建新记录。
    func recoverOnLaunch() async throws -> RecoveryReport
}

/// 启动恢复服务（CORE-003）。
///
/// 首版以口述记录状态机本身作为耐久化作业队列：每条非终态记录即一个
/// 可恢复作业，重启后经 `findIncomplete` 全部可发现，无需独立作业表，
/// 从机制上保证"不会重复创建记录"。
///
/// 恢复规则（`docs/ARCHITECTURE.md` §5.1）：
/// - `created`/`recording`/`queued`：录音文件有效 → `audioSaved`；
///   仅有半成品 → finalize 收养后 → `audioSaved`；否则 → `recordingFailed`；
/// - `transcribing` → `transcriptionFailed`（应用异常中断，可重试）；
/// - `transcribed`/`rewriting` → `rewriteFailed`（原始文字保留，可仅重新改写）；
/// - `ready`/`injecting` → `injectionFailed`（绝不自动向未知焦点重复输入）；
/// - 终态不处理。
///
/// 每次状态转移经状态机校验并由仓储同事务写入错误信息；单条记录恢复
/// 失败不影响其余记录（记录进诊断，继续扫描）。
public struct StartupRecoveryService: StartupRecovering {
    private let records: any DictationRecordRepository
    private let audioFiles: any AudioFileStore
    private let now: @Sendable () -> Date

    public init(
        records: any DictationRecordRepository,
        audioFiles: any AudioFileStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.records = records
        self.audioFiles = audioFiles
        self.now = now
    }

    public func recoverOnLaunch() async throws -> RecoveryReport {
        var report = RecoveryReport()
        let incomplete = try await records.findIncomplete()
        report.scannedCount = incomplete.count

        for record in incomplete {
            // 单条失败不中断整体扫描；损坏数据留待人工诊断。
            try? await recover(record: record, report: &report)
        }
        return report
    }

    // MARK: - 私有

    private func recover(record: DictationRecord, report: inout RecoveryReport) async throws {
        switch record.status {
        case .created, .recording, .queued:
            try await recoverRecordingStage(record: record, report: &report)
        case .transcribing:
            try await transition(
                record,
                to: .transcriptionFailed,
                error: DictationError(
                    category: .appInterrupted,
                    userMessage: "应用异常中断，转录未完成，可使用原录音重试"
                )
            )
            report.markedTranscriptionFailed.append(record.id)
        case .transcribed, .rewriting:
            try await transition(
                record,
                to: .rewriteFailed,
                error: DictationError(
                    category: .appInterrupted,
                    userMessage: "应用异常中断，改写未完成，可仅重新改写"
                )
            )
            report.markedRewriteFailed.append(record.id)
        case .ready, .injecting:
            try await transition(
                record,
                to: .injectionFailed,
                error: DictationError(
                    category: .appInterrupted,
                    userMessage: "应用异常中断，文字未自动输入，请复制或手动再次输入"
                )
            )
            report.markedInjectionFailed.append(record.id)
        case .audioSaved:
            // 音频已保存待转录：保持原状，用户可从历史发起转录，无需改动。
            break
        case .transcriptionFailed, .rewriteFailed, .injectionFailed,
             .recordingFailed, .completed, .cancelled:
            // 失败态已是可诊断的停滞态，终态不处理。
            break
        }
    }

    /// 录音阶段恢复：校验正式文件 → 收养半成品 → 标记失败。
    private func recoverRecordingStage(record: DictationRecord, report: inout RecoveryReport) async throws {
        guard let relativePath = record.audioRelativePath else {
            try await transition(record, to: .recordingFailed, error: interruptedRecordingError("录音文件路径缺失"))
            report.markedRecordingFailed.append(record.id)
            return
        }

        let info = try audioFiles.info(relativePath: relativePath)
        if info.exists, info.sizeBytes > 0 {
            try await transition(record, to: .audioSaved)
            report.restoredToAudioSaved.append(record.id)
            return
        }

        if audioFiles.hasPartial(relativePath: relativePath) {
            // finalize 会收养唯一文件名对应的半成品（属于同一条记录）。
            if let adopted = try? audioFiles.finalize(relativePath: relativePath), adopted.exists,
               adopted.sizeBytes > 0
            {
                var updated = record
                updated.audioSizeBytes = adopted.sizeBytes
                updated.updatedAt = now()
                try await records.save(updated)
                try await transition(record, to: .audioSaved)
                report.restoredToAudioSaved.append(record.id)
                report.adoptedPartialCount += 1
                return
            }
        }

        try await transition(record, to: .recordingFailed, error: interruptedRecordingError("录音文件缺失或损坏"))
        report.markedRecordingFailed.append(record.id)
    }

    private func interruptedRecordingError(_ message: String) -> DictationError {
        DictationError(
            category: .appInterrupted,
            userMessage: "应用异常中断，\(message)",
            isRetryable: false
        )
    }

    /// 状态转移：先经状态机校验，再由仓储同事务写入状态与错误。
    private func transition(
        _ record: DictationRecord,
        to target: DictationStatus,
        error: DictationError? = nil
    ) async throws {
        try DictationStateMachine.validateTransition(from: record.status, to: target)
        try await records.updateStatus(id: record.id, status: target, error: error, at: now())
    }
}
