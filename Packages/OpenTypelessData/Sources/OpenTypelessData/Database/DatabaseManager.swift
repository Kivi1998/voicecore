import Foundation
import GRDB
import OpenTypelessDomain

/// SQLite 数据库管理。
///
/// - 使用 GRDB `DatabasePool`（默认 WAL）管理连接与并发读写；
/// - 打开时启用外键约束并设置 busy timeout；
/// - 启动时在开放录音和写操作前执行迁移，迁移失败由上层进入只读错误页；
/// - 数据库文件与父目录权限限制为当前用户可访问（0700/0600）。
public final class DatabaseManager: Sendable {
    public let pool: DatabasePool
    public let databasePath: String

    /// 打开（必要时创建）数据库并执行全部待迁移。
    /// - Parameter path: SQLite 文件绝对路径。
    public init(path: String) throws {
        databasePath = path
        try DatabaseManager.prepareDirectory(for: path)

        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.label = "opentypeless.db"

        let pool = try DatabasePool(path: path, configuration: configuration)
        var migrator = DatabaseMigrator()
        Migrations.registerAll(in: &migrator)
        try migrator.migrate(pool)
        self.pool = pool

        try DatabaseManager.restrictPermissions(for: path)
    }

    /// 创建父目录并限制权限为当前用户可访问。
    static func prepareDirectory(for path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// 将数据库文件权限限制为当前用户可读写。
    static func restrictPermissions(for path: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }

    /// 已应用迁移标识（诊断与测试用）。
    public func appliedMigrationIdentifiers() throws -> [String] {
        var migrator = DatabaseMigrator()
        Migrations.registerAll(in: &migrator)
        return try pool.read { db in
            try migrator.appliedMigrations(db)
        }
    }
}
