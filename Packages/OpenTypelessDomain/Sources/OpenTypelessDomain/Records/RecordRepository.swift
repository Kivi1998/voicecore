import Foundation

/// 历史状态筛选。
public enum HistoryStatusFilter: String, Codable, Sendable, CaseIterable {
    case all
    /// 成功（completed）。
    case success
    /// 失败（各阶段失败状态）。
    case failure
    /// 收藏。
    case favorite
}

/// 稳定分页游标（按 started_at 与 id 双键排序）。
public struct RecordCursor: Sendable, Equatable {
    public var startedAt: Date
    public var recordID: UUID

    public init(startedAt: Date, recordID: UUID) {
        self.startedAt = startedAt
        self.recordID = recordID
    }
}

/// 历史查询条件。
///
/// 日期边界为 UTC；展示层负责把本地日期范围换算成 UTC 边界。
/// 分页必须使用游标，不允许一次加载全部记录。
public struct HistoryQuery: Sendable, Equatable {
    public static let defaultLimit = 50
    public static let maxLimit = 200

    /// 起始时间（含），UTC。
    public var startDate: Date?
    /// 结束时间（不含），UTC。
    public var endDate: Date?
    public var statusFilter: HistoryStatusFilter
    /// 全文搜索（匹配原始转录与最终文字）。
    public var searchText: String?
    public var cursor: RecordCursor?
    public var limit: Int

    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        statusFilter: HistoryStatusFilter = .all,
        searchText: String? = nil,
        cursor: RecordCursor? = nil,
        limit: Int = HistoryQuery.defaultLimit
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.statusFilter = statusFilter
        self.searchText = searchText
        self.cursor = cursor
        self.limit = min(max(1, limit), HistoryQuery.maxLimit)
    }
}

/// 一页历史记录。
public struct RecordPage: Sendable, Equatable {
    public var records: [DictationRecord]
    /// 下一页游标；nil 表示没有更多。
    public var nextCursor: RecordCursor?

    public init(records: [DictationRecord], nextCursor: RecordCursor?) {
        self.records = records
        self.nextCursor = nextCursor
    }
}

/// 口述记录仓储协议。
///
/// 上层只看到本协议与领域实体；SQL、事务和行映射封装在 OpenTypelessData。
/// 每次状态变化与关联字段更新必须处于同一数据库事务中。
public protocol DictationRecordRepository: Sendable {
    /// 新建记录（开始录音前必须先建立记录）。
    func create(_ record: DictationRecord) async throws

    /// 按标识读取。
    func get(id: UUID) async throws -> DictationRecord?

    /// 全量保存（字段级更新在事务内完成）。
    func save(_ record: DictationRecord) async throws

    /// 状态迁移：更新状态、错误字段和修改时间于同一事务；
    /// `error` 为 nil 时清除既有错误信息。
    func updateStatus(id: UUID, status: DictationStatus, error: DictationError?, at time: Date) async throws

    /// 组合筛选与游标分页查询。
    func query(_ query: HistoryQuery) async throws -> RecordPage

    /// 启动恢复扫描：所有未停滞（非终态）记录。
    func findIncomplete() async throws -> [DictationRecord]

    /// 删除记录（尝试记录级联删除；录音文件处理由上层按删除顺序编排）。
    func delete(id: UUID) async throws

    /// 追加一次尝试记录。
    func addAttempt(_ attempt: RecordAttempt) async throws

    /// 更新尝试记录（完成时写回成功、耗时、请求标识与错误）。
    func saveAttempt(_ attempt: RecordAttempt) async throws

    /// 读取记录的全部尝试，按阶段与次数排序。
    func attempts(recordID: UUID) async throws -> [RecordAttempt]

    /// 某阶段已有尝试次数（用于生成下一个 attempt_no 与乐观并发检查）。
    func attemptCount(recordID: UUID, stage: RecordAttempt.Stage) async throws -> Int
}
