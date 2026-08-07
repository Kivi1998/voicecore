import Foundation
import GRDB
import XCTest
@testable import OpenTypelessData

final class MigrationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentypeless-migration-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeManager() throws -> DatabaseManager {
        try DatabaseManager(path: tempDirectory.appendingPathComponent("app.sqlite3").path)
    }

    /// 空数据库可一次迁移到最新版本（DATA_MODEL §10）。
    func testEmptyDatabaseMigratesToLatest() throws {
        let manager = try makeManager()
        let tables = try manager.pool.read { db -> Set<String> in
            let rows = try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            return Set(rows.map { $0["name"] as String })
        }
        XCTAssertTrue(tables.contains("dictation_records"))
        XCTAssertTrue(tables.contains("record_attempts"))
        XCTAssertTrue(tables.contains("provider_profiles"))
        XCTAssertTrue(tables.contains("dictionary_terms"))
        XCTAssertTrue(tables.contains("app_settings"))
        XCTAssertEqual(try manager.appliedMigrationIdentifiers(), Migrations.publishedMigrationIdentifiers)
    }

    /// 迁移可重复执行（重复启动不会重复执行或破坏）。
    func testMigrationIsRepeatable() throws {
        let manager = try makeManager()
        var migrator = DatabaseMigrator()
        Migrations.registerAll(in: &migrator)
        XCTAssertNoThrow(try migrator.migrate(manager.pool))
        XCTAssertEqual(try manager.appliedMigrationIdentifiers(), Migrations.publishedMigrationIdentifiers)
    }

    /// 已发布迁移清单快照：防止旧迁移被重命名、删除或改变顺序。
    func testPublishedMigrationListIsFrozen() {
        XCTAssertEqual(Migrations.publishedMigrationIdentifiers, ["v0001_initial"])
    }

    /// 外键约束生效：引用不存在配置的记录被拒绝。
    func testForeignKeyEnforced() throws {
        let manager = try makeManager()
        XCTAssertThrowsError(try manager.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO dictation_records
                (id, status, started_at, speech_profile_id, speech_snapshot_json, created_at, updated_at)
                VALUES (?, 'created', ?, ?, '{}', ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    UTCTimestamp.now(),
                    UUID().uuidString,
                    UTCTimestamp.now(),
                    UTCTimestamp.now(),
                ]
            )
        })
    }

    /// 词典归一化词唯一索引生效。
    func testDictionaryUniqueNormalizedTerm() throws {
        let manager = try makeManager()
        try manager.pool.write { db in
            try db.execute(
                sql: "INSERT INTO dictionary_terms (id, term, normalized_term, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, "OpenAI", "openai", UTCTimestamp.now(), UTCTimestamp.now()]
            )
        }
        XCTAssertThrowsError(try manager.pool.write { db in
            try db.execute(
                sql: "INSERT INTO dictionary_terms (id, term, normalized_term, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, "openai", "openai", UTCTimestamp.now(), UTCTimestamp.now()]
            )
        })
    }

    /// 删除记录时尝试记录级联删除。
    func testAttemptsCascadeDelete() throws {
        let manager = try makeManager()
        let recordID = UUID().uuidString
        try manager.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO dictation_records
                (id, status, started_at, speech_snapshot_json, created_at, updated_at)
                VALUES (?, 'created', ?, '{}', ?, ?)
                """,
                arguments: [recordID, UTCTimestamp.now(), UTCTimestamp.now(), UTCTimestamp.now()]
            )
            try db.execute(
                sql: """
                INSERT INTO record_attempts (id, record_id, stage, attempt_no, started_at)
                VALUES (?, ?, 'transcription', 1, ?)
                """,
                arguments: [UUID().uuidString, recordID, UTCTimestamp.now()]
            )
        }
        try manager.pool.write { db in
            try db.execute(sql: "DELETE FROM dictation_records WHERE id = ?", arguments: [recordID])
        }
        let attemptCount = try manager.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_attempts WHERE record_id = ?", arguments: [recordID])
        }
        XCTAssertEqual(attemptCount, 0)
    }

    /// 数据库文件权限限制为当前用户可访问。
    func testDatabaseFilePermissionsRestricted() throws {
        let manager = try makeManager()
        _ = manager
        let attributes = try FileManager.default.attributesOfItem(
            atPath: tempDirectory.appendingPathComponent("app.sqlite3").path
        )
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue & 0o777, 0o600)
    }

    /// UTC 时间编码往返。
    func testUTCTimestampRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_786_003_200.123)
        let string = UTCTimestamp.string(from: date)
        XCTAssertTrue(string.hasPrefix("2026-08-06T"))
        XCTAssertTrue(string.hasSuffix("Z"))
        let parsed = try XCTUnwrap(UTCTimestamp.date(from: string))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }
}
