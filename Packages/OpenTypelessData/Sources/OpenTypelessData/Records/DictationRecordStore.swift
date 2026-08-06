import Foundation
import GRDB
import OpenTypelessDomain

/// 口述记录仓储的 GRDB 实现。
///
/// 事务边界：
/// - 每次状态变化与关联字段更新在同一事务；
/// - 写操作使用短事务，禁止跨网络请求持有事务。
public struct DictationRecordStore: DictationRecordRepository {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func create(_ record: DictationRecord) async throws {
        let row = try DBDictationRecord(domain: record)
        try await pool.write { db in
            try row.insert(db)
        }
    }

    public func get(id: UUID) async throws -> DictationRecord? {
        let key = id.uuidString.lowercased()
        return try await pool.read { db in
            try DBDictationRecord.fetchOne(db, key: key)?.toDomain()
        }
    }

    public func save(_ record: DictationRecord) async throws {
        let row = try DBDictationRecord(domain: record)
        try await pool.write { db in
            try row.update(db)
        }
    }

    public func updateStatus(id: UUID, status: DictationStatus, error: DictationError?, at time: Date) async throws {
        let key = id.uuidString.lowercased()
        let timestamp = UTCTimestamp.string(from: time)
        try await pool.write { db in
            guard let row = try DBDictationRecord.fetchOne(db, key: key) else {
                throw DictationError(
                    category: .unknown,
                    userMessage: "记录不存在",
                    isRetryable: false
                )
            }
            var updated = row
            updated.status = status.rawValue
            updated.updatedAt = timestamp
            // 新状态未携带错误时清除旧错误信息，避免陈旧提示。
            updated.lastErrorCategory = error?.category.rawValue
            updated.lastErrorMessage = error?.userMessage
            try updated.update(db, columns: [
                Column("status"),
                Column("updated_at"),
                Column("last_error_category"),
                Column("last_error_message"),
            ])
        }
    }

    public func query(_ query: HistoryQuery) async throws -> RecordPage {
        try await pool.read { db in
            var request = DBDictationRecord.all()

            if let startDate = query.startDate {
                request = request.filter(Column("started_at") >= UTCTimestamp.string(from: startDate))
            }
            if let endDate = query.endDate {
                request = request.filter(Column("started_at") < UTCTimestamp.string(from: endDate))
            }
            switch query.statusFilter {
            case .all:
                break
            case .success:
                request = request.filter(Column("status") == DictationStatus.completed.rawValue)
            case .failure:
                let failures: [String] = [
                    DictationStatus.transcriptionFailed.rawValue,
                    DictationStatus.rewriteFailed.rawValue,
                    DictationStatus.injectionFailed.rawValue,
                    DictationStatus.recordingFailed.rawValue,
                ]
                request = request.filter(failures.contains(Column("status")))
            case .favorite:
                request = request.filter(Column("is_favorite") == true)
            }
            if let search = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !search.isEmpty {
                let pattern = "%\(Self.escapeLike(search))%"
                request = request.filter(
                    Column("raw_transcript").like(pattern, escape: "\\")
                        || Column("final_text").like(pattern, escape: "\\")
                )
            }

            // 排序：started_at DESC, id DESC；游标条件与排序一致保证分页稳定。
            if let cursor = query.cursor {
                let cursorTime = UTCTimestamp.string(from: cursor.startedAt)
                let cursorID = cursor.recordID.uuidString.lowercased()
                request = request.filter(
                    Column("started_at") < cursorTime
                        || (Column("started_at") == cursorTime && Column("id") < cursorID)
                )
            }
            request = request
                .order(Column("started_at").desc, Column("id").desc)
                .limit(query.limit + 1)

            let rows = try request.fetchAll(db)
            let hasMore = rows.count > query.limit
            let pageRows = hasMore ? Array(rows.dropLast()) : rows
            let records = try pageRows.map { try $0.toDomain() }
            let nextCursor = hasMore ? records.last.map {
                RecordCursor(startedAt: $0.startedAt, recordID: $0.id)
            } : nil
            return RecordPage(records: records, nextCursor: nextCursor)
        }
    }

    public func findIncomplete() async throws -> [DictationRecord] {
        try await pool.read { db in
            let settled: [String] = DictationStatus.allCases.filter(\.isSettled).map(\.rawValue)
            return try DBDictationRecord
                .filter(!settled.contains(Column("status")))
                .order(Column("started_at"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func delete(id: UUID) async throws {
        let key = id.uuidString.lowercased()
        try await pool.write { db in
            _ = try DBDictationRecord.deleteOne(db, key: key)
        }
    }

    public func addAttempt(_ attempt: RecordAttempt) async throws {
        let row = DBRecordAttempt(domain: attempt)
        try await pool.write { db in
            try row.insert(db)
        }
    }

    public func saveAttempt(_ attempt: RecordAttempt) async throws {
        let row = DBRecordAttempt(domain: attempt)
        try await pool.write { db in
            try row.update(db)
        }
    }

    public func unitsSummary(from start: Date?, to end: Date?) async throws -> UnitsSummary {
        try await pool.read { db in
            var sql = """
                SELECT COALESCE(SUM(count_units), 0) AS total_units, COUNT(*) AS record_count
                FROM dictation_records
                WHERE final_text IS NOT NULL
                """
            var arguments = StatementArguments()
            if let start {
                sql += " AND started_at >= ?"
                arguments += [UTCTimestamp.string(from: start)]
            }
            if let end {
                sql += " AND started_at < ?"
                arguments += [UTCTimestamp.string(from: end)]
            }
            guard let row = try Row.fetchOne(db, sql: sql, arguments: arguments) else {
                return .zero
            }
            return UnitsSummary(
                totalUnits: row["total_units"],
                recordCount: row["record_count"]
            )
        }
    }

    public func unitEntries(from start: Date, to end: Date?) async throws -> [UnitEntry] {
        try await pool.read { db in
            var sql = """
                SELECT started_at, count_units
                FROM dictation_records
                WHERE final_text IS NOT NULL AND started_at >= ?
                """
            var arguments = StatementArguments()
            arguments += [UTCTimestamp.string(from: start)]
            if let end {
                sql += " AND started_at < ?"
                arguments += [UTCTimestamp.string(from: end)]
            }
            sql += " ORDER BY started_at"
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap { row in
                guard let startedAtString: String = row["started_at"],
                      let startedAt = UTCTimestamp.date(from: startedAtString) else {
                    return nil
                }
                let units: Int64 = row["count_units"]
                return UnitEntry(startedAt: startedAt, units: units)
            }
        }
    }

    public func attempts(recordID: UUID) async throws -> [RecordAttempt] {
        let key = recordID.uuidString.lowercased()
        return try await pool.read { db in
            try DBRecordAttempt
                .filter(Column("record_id") == key)
                .order(Column("stage"), Column("attempt_no"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func attemptCount(recordID: UUID, stage: RecordAttempt.Stage) async throws -> Int {
        let key = recordID.uuidString.lowercased()
        return try await pool.read { db in
            try DBRecordAttempt
                .filter(Column("record_id") == key && Column("stage") == stage.rawValue)
                .fetchCount(db)
        }
    }

    /// LIKE 通配符转义，防止用户输入被解释为模式字符。
    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
