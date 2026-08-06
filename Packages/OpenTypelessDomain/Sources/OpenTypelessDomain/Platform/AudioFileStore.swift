import Foundation

/// 录音文件元信息。
public struct AudioFileInfo: Sendable, Equatable {
    public var relativePath: String
    public var sizeBytes: Int64
    public var exists: Bool

    public init(relativePath: String, sizeBytes: Int64, exists: Bool) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.exists = exists
    }
}

/// 录音文件仓储协议。
///
/// 规则（docs/DATA_MODEL.md §1、§5）：
/// - 数据库只保存相对录音根目录路径；
/// - 写入必须原子：先写临时文件再移动就位，异常不产生半成品覆盖；
/// - 删除先校验路径，防止目录穿越。
public protocol AudioFileStore: Sendable {
    /// 为新录音准备目标相对路径并确保父目录存在。
    /// 文件名使用记录 UUID，按年/月/日分目录，不使用口述内容命名。
    func prepareDestination(recordID: UUID, startedAt: Date, fileExtension: String) throws -> String

    /// 返回可追加写入的文件句柄（采集模块边录边写）。
    func openForWriting(relativePath: String) throws -> AudioFileWriting

    /// 录音结束后安全关闭并校验：文件存在、非空、可读取头。
    func finalize(relativePath: String) throws -> AudioFileInfo

    /// 读取文件信息；文件不存在时 exists 为 false。
    func info(relativePath: String) throws -> AudioFileInfo

    /// 删除录音文件（同时清理未完成半成品）；文件不存在视为成功，
    /// 缺失情况由调用方记日志。返回是否实际删除了文件。
    @discardableResult
    func delete(relativePath: String) throws -> Bool

    /// 是否存在未完成的半成品文件（用于崩溃恢复诊断）。
    func hasPartial(relativePath: String) -> Bool

    /// 列出全部正式录音相对路径（一致性检查用，不得包含半成品）。
    func listRecordingRelativePaths() throws -> [String]

    /// 录音总占用空间（字节，含半成品）。
    func totalSizeBytes() throws -> Int64
}

/// 录音写入句柄：采集回调线程只做有界缓冲与写盘调度。
public protocol AudioFileWriting: Sendable {
    /// 追加数据；立即落盘，不在内存累积完整录音。
    func append(_ data: Data) throws
    /// 关闭句柄（幂等）。
    func close() throws
}
