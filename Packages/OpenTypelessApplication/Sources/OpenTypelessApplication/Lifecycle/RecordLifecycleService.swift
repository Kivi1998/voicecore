import Foundation
import OpenTypelessDomain

/// 删除报告（界面反馈与诊断）。
public struct DeleteReport: Sendable, Equatable {
    /// 实际删除的记录数。
    public var deletedCount = 0
    /// 释放的录音字节数（按删除前文件大小估算）。
    public var freedAudioBytes: Int64 = 0
    /// 数据库有路径但文件已缺失的记录数（删除照常完成）。
    public var missingAudioCount = 0

    public init() {}
}

/// 记录生命周期服务（DATA-006）。
///
/// 删除顺序编排：先删录音文件（含半成品），再删数据库记录
/// （尝试记录经外键级联删除）。顺序保证异常中断后不会出现
/// "数据库已删、磁盘残留未知文件"的空间泄漏；残留的
/// "无音频记录"可由历史页面正常展示并再次删除。
///
/// 规则：
/// - 删除必须由界面明确确认后调用（本服务不做确认交互）；
/// - 收藏记录与普通话记录走完全相同的路径，无特殊删除保护漏洞；
/// - 绝不自动清理：本服务只响应用户显式操作。
public struct RecordLifecycleService: Sendable {
    private let records: any DictationRecordRepository
    private let audioFiles: any AudioFileStore

    public init(records: any DictationRecordRepository, audioFiles: any AudioFileStore) {
        self.records = records
        self.audioFiles = audioFiles
    }

    /// 删除单条记录及其录音；记录不存在时视为成功（幂等）。
    @discardableResult
    public func deleteRecord(id: UUID) async throws -> DeleteReport {
        try await deleteRecords(ids: [id])
    }

    /// 批量删除（历史多选与设置页手动清理；范围选择与二次确认由界面完成）。
    @discardableResult
    public func deleteRecords(ids: [UUID]) async throws -> DeleteReport {
        var report = DeleteReport()
        for id in ids {
            guard let record = try await records.get(id: id) else { continue }

            if let path = record.audioRelativePath {
                let size = (try? audioFiles.info(relativePath: path).sizeBytes) ?? 0
                let removed = try audioFiles.delete(relativePath: path)
                if removed {
                    report.freedAudioBytes += size
                } else {
                    report.missingAudioCount += 1
                }
            }
            try await records.delete(id: id)
            report.deletedCount += 1
        }
        return report
    }
}

/// 存储占用统计（设置页展示；不存在自动清理，仅展示与人工操作）。
public struct StorageUsage: Sendable, Equatable {
    /// 录音文件总占用（含半成品）。
    public var audioBytes: Int64
    /// 数据库文件占用。
    public var databaseBytes: Int64
    /// 历史记录总条数。
    public var recordCount: Int

    public init(audioBytes: Int64, databaseBytes: Int64, recordCount: Int) {
        self.audioBytes = audioBytes
        self.databaseBytes = databaseBytes
        self.recordCount = recordCount
    }

    public var totalBytes: Int64 {
        audioBytes + databaseBytes
    }
}

/// 存储统计服务（DATA-006）。
public struct StorageStatisticsService: Sendable {
    private let records: any DictationRecordRepository
    private let audioFiles: any AudioFileStore
    /// 数据库文件大小提供者（组合根注入，避免应用层感知数据库路径）。
    private let databaseSizeBytes: @Sendable () throws -> Int64

    public init(
        records: any DictationRecordRepository,
        audioFiles: any AudioFileStore,
        databaseSizeBytes: @escaping @Sendable () throws -> Int64
    ) {
        self.records = records
        self.audioFiles = audioFiles
        self.databaseSizeBytes = databaseSizeBytes
    }

    public func usage() async throws -> StorageUsage {
        async let audio = Task { try audioFiles.totalSizeBytes() }.value
        async let count = records.recordCount()
        let database = (try? databaseSizeBytes()) ?? 0
        return try await StorageUsage(
            audioBytes: audio,
            databaseBytes: database,
            recordCount: count
        )
    }
}
