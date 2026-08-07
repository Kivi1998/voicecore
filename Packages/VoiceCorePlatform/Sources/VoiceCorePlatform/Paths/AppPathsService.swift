import Foundation
import VoiceCoreDomain

/// macOS 应用路径服务（组合根使用）。
///
/// 数据根目录：`~/Library/Application Support/<bundle-id>/`，
/// 首次访问时创建（0700 权限）；数据库只保存相对录音路径，
/// 数据根移动后可重新定位。
public struct AppPathsService: PathService {
    public let dataRoot: URL
    public let recordingsRoot: URL
    public let tempRoot: URL
    public let logsRoot: URL
    public let backupsRoot: URL

    /// - Parameter bundleIdentifier: 应用 Bundle ID（目录名）。
    public init(bundleIdentifier: String) throws {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DictationError(
                category: .unknown,
                userMessage: "无法定位应用数据目录",
                isRetryable: false
            )
        }
        let root = appSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
        dataRoot = root
        recordingsRoot = root.appendingPathComponent("recordings", isDirectory: true)
        tempRoot = root.appendingPathComponent("tmp", isDirectory: true)
        logsRoot = root.appendingPathComponent("logs", isDirectory: true)
        backupsRoot = root.appendingPathComponent("backups", isDirectory: true)

        for directory in [root, recordingsRoot, tempRoot, logsRoot, backupsRoot] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}
