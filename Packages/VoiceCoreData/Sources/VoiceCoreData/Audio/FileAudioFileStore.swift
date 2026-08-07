import Foundation
import VoiceCoreDomain

/// 录音文件仓储的本地文件系统实现。
///
/// 原子性设计：
/// - 采集时写入 `<name>.partial` 半成品文件，边录边落盘；
/// - `finalize` 校验后重命名为正式文件，异常退出只残留 `.partial`，
///   绝不会出现"看似完整的损坏文件"或半成品覆盖既有录音；
/// - 恢复时 `finalize` 可收养残留半成品（唯一文件名的半成品属于同一条记录）。
public struct FileAudioFileStore: AudioFileStore {
    /// 半成品文件后缀。
    public static let partialSuffix = ".partial"

    private let recordingsRoot: URL

    /// FileManager 非 Sendable，不作为存储属性持有；统一使用
    /// `FileManager.default`（线程安全，Apple 文档允许并发调用）。
    private var fileManager: FileManager {
        .default
    }

    public init(recordingsRoot: URL) {
        self.recordingsRoot = recordingsRoot
    }

    public func prepareDestination(recordID: UUID, startedAt: Date, fileExtension: String) throws -> String {
        let relativePath = RecordingRelativePath.make(
            recordID: recordID,
            startedAt: startedAt,
            fileExtension: fileExtension
        )
        let directory = try resolve(relativePath: relativePath).deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return relativePath
    }

    public func openForWriting(relativePath: String) throws -> AudioFileWriting {
        let partialURL = try partialURL(for: relativePath)
        try fileManager.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // 半成品已存在说明同记录重试或异常残留；删除旧半成品重新开始，
        // 正式文件不受影响。
        try? fileManager.removeItem(at: partialURL)
        guard fileManager.createFile(atPath: partialURL.path, contents: nil) else {
            throw DictationError(
                category: .audioWriteFailed,
                userMessage: "无法创建录音文件，请检查磁盘空间和目录权限"
            )
        }
        do {
            let handle = try FileHandle(forWritingTo: partialURL)
            return FileAudioWriter(handle: handle)
        } catch {
            throw DictationError(
                category: .audioWriteFailed,
                userMessage: "无法打开录音文件进行写入"
            )
        }
    }

    public func finalize(relativePath: String) throws -> AudioFileInfo {
        let finalURL = try resolve(relativePath: relativePath)
        let partial = try partialURL(for: relativePath)

        if !fileManager.fileExists(atPath: finalURL.path) {
            guard fileManager.fileExists(atPath: partial.path) else {
                throw DictationError(
                    category: .audioInvalid,
                    userMessage: "录音文件缺失",
                    isRetryable: false
                )
            }
            do {
                try fileManager.moveItem(at: partial, to: finalURL)
            } catch {
                throw DictationError(
                    category: .audioWriteFailed,
                    userMessage: "录音文件保存失败"
                )
            }
        } else {
            // 正式文件已存在（重复 finalize）；清理可能残留的半成品。
            try? fileManager.removeItem(at: partial)
        }

        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: finalURL.path)

        let info = try info(relativePath: relativePath)
        guard info.exists, info.sizeBytes > 0 else {
            throw DictationError(
                category: .audioInvalid,
                userMessage: "录音文件为空或不可读",
                isRetryable: false
            )
        }
        // 基本完整性检查：文件头可读取（格式级校验由音频模块负责）。
        guard let handle = try? FileHandle(forReadingFrom: finalURL) else {
            throw DictationError(category: .audioInvalid, userMessage: "录音文件不可读", isRetryable: false)
        }
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard !header.isEmpty else {
            throw DictationError(category: .audioInvalid, userMessage: "录音文件内容为空", isRetryable: false)
        }
        return info
    }

    public func info(relativePath: String) throws -> AudioFileInfo {
        let url = try resolve(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return AudioFileInfo(relativePath: relativePath, sizeBytes: 0, exists: false)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return AudioFileInfo(relativePath: relativePath, sizeBytes: size, exists: true)
    }

    @discardableResult
    public func delete(relativePath: String) throws -> Bool {
        let finalURL = try resolve(relativePath: relativePath)
        let partial = try partialURL(for: relativePath)
        var removed = false
        if fileManager.fileExists(atPath: partial.path) {
            try fileManager.removeItem(at: partial)
            removed = true
        }
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
            removed = true
        }
        return removed
    }

    public func hasPartial(relativePath: String) -> Bool {
        guard RecordingRelativePath.isValid(relativePath) else { return false }
        return (try? partialURL(for: relativePath)).map { fileManager.fileExists(atPath: $0.path) } ?? false
    }

    public func listRecordingRelativePaths() throws -> [String] {
        var paths: [String] = []
        // 使用 enumerator(atPath:)：返回相对路径字符串，避免 URL 枚举在
        // /var → /private/var 符号链接下绝对路径前缀比较失效的问题。
        guard let enumerator = fileManager.enumerator(atPath: recordingsRoot.path) else { return [] }
        for case let relative as String in enumerator {
            if relative.hasSuffix(Self.partialSuffix) {
                continue
            }
            guard RecordingRelativePath.isValid(relative) else { continue }
            let full = recordingsRoot.appendingPathComponent(relative, isDirectory: false)
            let values = try full.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            paths.append(relative)
        }
        return paths.sorted()
    }

    public func totalSizeBytes() throws -> Int64 {
        guard fileManager.fileExists(atPath: recordingsRoot.path) else { return 0 }
        guard let enumerator = fileManager.enumerator(
            at: recordingsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    // MARK: - 私有

    private func resolve(relativePath: String) throws -> URL {
        // 数据库中损坏的路径属于正常运行时可遇到的输入，必须抛出
        // 可诊断错误，不得使用 precondition/fatalError。
        guard RecordingRelativePath.isValid(relativePath) else {
            throw DictationError(
                category: .audioInvalid,
                userMessage: "录音文件路径无效",
                isRetryable: false
            )
        }
        return recordingsRoot.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func partialURL(for relativePath: String) throws -> URL {
        try resolve(relativePath: relativePath + Self.partialSuffix)
    }
}

/// FileHandle 录音写入器。
///
/// FileHandle 非 Sendable，这里用锁保证 `append`/`close` 的串行访问；
/// 采集回调线程只做写盘，不执行数据库或网络操作。
final class FileAudioWriter: AudioFileWriting, @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var isClosed = false

    init(handle: FileHandle) {
        self.handle = handle
    }

    func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else {
            throw DictationError(
                category: .audioWriteFailed,
                userMessage: "录音文件已关闭",
                isRetryable: false
            )
        }
        try handle.write(contentsOf: data)
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        try handle.close()
    }
}
