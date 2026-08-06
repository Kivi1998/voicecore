import Foundation

/// 录音相对路径校验与拼接（纯函数，供各平台与数据层共用）。
///
/// 规则：非空、不能以 `/` 开头、不允许 `..` 路径分量、不允许空分量，
/// 防止目录穿越和数据根目录误删。
public enum RecordingRelativePath {
    /// 校验相对路径是否合法。
    public static func isValid(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        for component in components {
            if component.isEmpty || component == "." || component == ".." {
                return false
            }
        }
        return true
    }

    /// 按年/月/日分目录生成录音相对路径，例如 `2026/08/06/<uuid>.m4a`。
    /// - Parameters:
    ///   - recordID: 记录标识（不使用口述内容命名）。
    ///   - date: 录音开始时间（UTC）。
    ///   - fileExtension: 扩展名，不含点号。
    public static func make(recordID: UUID, startedAt date: Date, fileExtension: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(
            format: "%04d/%02d/%02d/%@.%@",
            year, month, day, recordID.uuidString.lowercased(), fileExtension
        )
    }
}

/// 目录与路径能力协议。
///
/// 数据根目录为 `~/Library/Application Support/<bundle-id>/`；
/// 数据库只保存相对录音路径，移动数据根目录后可重新定位。
public protocol PathService: Sendable {
    /// 数据根目录。
    var dataRoot: URL { get }
    /// 录音根目录（`dataRoot/recordings`）。
    var recordingsRoot: URL { get }
    /// 临时目录（转码等派生文件）。
    var tempRoot: URL { get }
    /// 日志目录。
    var logsRoot: URL { get }
    /// 备份目录。
    var backupsRoot: URL { get }

    /// 解析录音相对路径为绝对 URL。
    /// - Throws: 相对路径非法（目录穿越等）时抛出 `DictationError`。
    func resolveRecording(relativePath: String) throws -> URL
}

extension PathService {
    /// 默认解析实现：校验相对路径后拼接录音根目录。
    public func resolveRecording(relativePath: String) throws -> URL {
        guard RecordingRelativePath.isValid(relativePath) else {
            throw DictationError(
                category: .audioInvalid,
                userMessage: "录音文件路径无效",
                isRetryable: false
            )
        }
        return recordingsRoot.appendingPathComponent(relativePath, isDirectory: false)
    }
}
