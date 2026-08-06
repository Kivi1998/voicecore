import Foundation
import OpenTypelessDomain

/// 历史导出信封（JSON 格式 v1）。
///
/// 安全规则（`docs/ARCHITECTURE.md` §9、KIMI_PROMPT 安全红线）：
/// - 默认且永远不包含 API 密钥与鉴权头——提供商信息只导出脱敏快照
///   （名称、协议、Base URL、模型名）；
/// - 不导出任何文件路径（含相对路径），只导出音频元信息；
/// - 导出文件权限 0600，原子写入（先临时文件再改名）。
public struct HistoryExportEnvelope: Codable, Sendable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var recordCount: Int
    public var records: [ExportedRecord]

    public init(formatVersion: Int, exportedAt: Date, recordCount: Int, records: [ExportedRecord]) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.recordCount = recordCount
        self.records = records
    }
}

/// 导出的单条口述记录。
public struct ExportedRecord: Codable, Sendable {
    public var id: UUID
    public var status: String
    public var startedAt: Date
    public var stoppedAt: Date?
    public var completedAt: Date?
    public var durationMs: Int64
    public var audioMimeType: String?
    public var audioSizeBytes: Int64?
    public var audioSHA256: String?
    public var rawTranscript: String?
    public var finalText: String?
    public var countUnits: Int64
    public var detectedLanguage: String?
    public var isFavorite: Bool
    public var speechProfile: ProviderProfileSnapshot
    public var rewriteProfile: ProviderProfileSnapshot?
    public var lastErrorCategory: String?
    public var lastErrorMessage: String?
    public var retryCount: Int

    public init(record: DictationRecord) {
        id = record.id
        status = record.status.rawValue
        startedAt = record.startedAt
        stoppedAt = record.stoppedAt
        completedAt = record.completedAt
        durationMs = record.durationMs
        audioMimeType = record.audioMimeType
        audioSizeBytes = record.audioSizeBytes
        audioSHA256 = record.audioSHA256
        rawTranscript = record.rawTranscript
        finalText = record.finalText
        countUnits = record.countUnits
        detectedLanguage = record.detectedLanguage
        isFavorite = record.isFavorite
        speechProfile = record.speechSnapshot
        rewriteProfile = record.rewriteSnapshot
        lastErrorCategory = record.lastErrorCategory?.rawValue
        lastErrorMessage = record.lastErrorMessage
        retryCount = record.retryCount
    }
}

/// 导出结果。
public struct ExportReport: Sendable, Equatable {
    public var recordCount: Int
    public var fileBytes: Int64

    public init(recordCount: Int, fileBytes: Int64) {
        self.recordCount = recordCount
        self.fileBytes = fileBytes
    }
}

/// 历史导出服务（DATA-006）。
///
/// 分页读取全量历史（游标分页，禁止一次性全量加载到内存以外的
/// 中间存储——导出本身需要一个 JSON 文档，因此流式分页累积编码，
/// 每页读完即编码释放行对象）。
public struct HistoryExportService: Sendable {
    /// 当前导出格式版本。
    public static let formatVersion = 1

    private let records: any DictationRecordRepository
    private let now: @Sendable () -> Date

    public init(
        records: any DictationRecordRepository,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.records = records
        self.now = now
    }

    /// 导出全部历史到指定 URL（原子写入，覆盖已有文件）。
    /// - Returns: 导出条数与文件字节数。
    @discardableResult
    public func export(to url: URL) async throws -> ExportReport {
        var exported: [ExportedRecord] = []
        var cursor: RecordCursor?
        while true {
            let page = try await records.query(HistoryQuery(cursor: cursor, limit: HistoryQuery.maxLimit))
            exported.append(contentsOf: page.records.map(ExportedRecord.init(record:)))
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        // 导出按时间升序，便于阅读与 diff。
        exported.sort { $0.startedAt < $1.startedAt }

        let envelope = HistoryExportEnvelope(
            formatVersion: Self.formatVersion,
            exportedAt: now(),
            recordCount: exported.count,
            records: exported
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }

        return ExportReport(recordCount: exported.count, fileBytes: Int64(data.count))
    }
}
