import Foundation
import GRDB
import VoiceCoreDomain

/// `dictation_records` 行映射。
///
/// 时间以 UTC RFC 3339 文本存储；快照为脱敏 JSON。
struct DBDictationRecord: Codable, TableRecord, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "dictation_records"

    var id: String
    var status: String
    var startedAt: String
    var stoppedAt: String?
    var completedAt: String?
    var durationMs: Int64
    var audioRelPath: String?
    var audioMimeType: String?
    var audioSizeBytes: Int64?
    var audioSha256: String?
    var rawTranscript: String?
    var finalText: String?
    var countUnits: Int64
    var detectedLanguage: String?
    var isFavorite: Bool
    var speechProfileId: String?
    var rewriteProfileId: String?
    var speechSnapshotJson: String
    var rewriteSnapshotJson: String?
    var lastErrorCategory: String?
    var lastErrorMessage: String?
    var retryCount: Int
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case durationMs = "duration_ms"
        case rawTranscript = "raw_transcript"
        case finalText = "final_text"
        case countUnits = "count_units"
        case detectedLanguage = "detected_language"
        case isFavorite = "is_favorite"
        case lastErrorCategory = "last_error_category"
        case lastErrorMessage = "last_error_message"
        case retryCount = "retry_count"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
        case completedAt = "completed_at"
        case audioRelPath = "audio_rel_path"
        case audioMimeType = "audio_mime_type"
        case audioSizeBytes = "audio_size_bytes"
        case audioSha256 = "audio_sha256"
        case speechProfileId = "speech_profile_id"
        case rewriteProfileId = "rewrite_profile_id"
        case speechSnapshotJson = "speech_snapshot_json"
        case rewriteSnapshotJson = "rewrite_snapshot_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension DBDictationRecord {
    /// 编码模型快照为 JSON 文本；UTF-8 转换失败时抛出可诊断错误。
    private static func encodeSnapshot(_ snapshot: ProviderProfileSnapshot) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DictationError(category: .unknown, userMessage: "模型快照编码失败", isRetryable: false)
        }
        return json
    }

    init(domain record: DictationRecord) throws {
        id = record.id.uuidString.lowercased()
        status = record.status.rawValue
        startedAt = UTCTimestamp.string(from: record.startedAt)
        stoppedAt = record.stoppedAt.map(UTCTimestamp.string(from:))
        completedAt = record.completedAt.map(UTCTimestamp.string(from:))
        durationMs = record.durationMs
        audioRelPath = record.audioRelativePath
        audioMimeType = record.audioMimeType
        audioSizeBytes = record.audioSizeBytes
        audioSha256 = record.audioSHA256
        rawTranscript = record.rawTranscript
        finalText = record.finalText
        countUnits = record.countUnits
        detectedLanguage = record.detectedLanguage
        isFavorite = record.isFavorite
        speechProfileId = record.speechProfileID?.uuidString.lowercased()
        rewriteProfileId = record.rewriteProfileID?.uuidString.lowercased()
        speechSnapshotJson = try Self.encodeSnapshot(record.speechSnapshot)
        rewriteSnapshotJson = try record.rewriteSnapshot.map(Self.encodeSnapshot)
        lastErrorCategory = record.lastErrorCategory?.rawValue
        lastErrorMessage = record.lastErrorMessage
        retryCount = record.retryCount
        createdAt = UTCTimestamp.string(from: record.createdAt)
        updatedAt = UTCTimestamp.string(from: record.updatedAt)
    }

    private static func parseDate(_ string: String, _ field: String) throws -> Date {
        guard let date = UTCTimestamp.date(from: string) else {
            throw DictationError(
                category: .unknown,
                userMessage: "数据库时间字段损坏：\(field)",
                isRetryable: false
            )
        }
        return date
    }

    private static func decodeSnapshot(_ json: String?) -> ProviderProfileSnapshot? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProviderProfileSnapshot.self, from: data)
    }

    /// 转换为领域实体；数据损坏（非法时间、状态、快照）时抛出可诊断错误。
    func toDomain() throws -> DictationRecord {
        guard let recordID = UUID(uuidString: id) else {
            throw DictationError(category: .unknown, userMessage: "记录标识损坏", isRetryable: false)
        }
        guard let statusValue = DictationStatus(rawValue: status) else {
            throw DictationError(category: .unknown, userMessage: "记录状态损坏：\(status)", isRetryable: false)
        }
        guard let snapshot = Self.decodeSnapshot(speechSnapshotJson) else {
            throw DictationError(category: .unknown, userMessage: "模型快照损坏", isRetryable: false)
        }
        return try DictationRecord(
            id: recordID,
            status: statusValue,
            startedAt: Self.parseDate(startedAt, "started_at"),
            stoppedAt: stoppedAt.map { try Self.parseDate($0, "stopped_at") },
            completedAt: completedAt.map { try Self.parseDate($0, "completed_at") },
            durationMs: durationMs,
            audioRelativePath: audioRelPath,
            audioMimeType: audioMimeType,
            audioSizeBytes: audioSizeBytes,
            audioSHA256: audioSha256,
            rawTranscript: rawTranscript,
            finalText: finalText,
            countUnits: countUnits,
            detectedLanguage: detectedLanguage,
            isFavorite: isFavorite,
            speechProfileID: speechProfileId.flatMap { UUID(uuidString: $0) },
            rewriteProfileID: rewriteProfileId.flatMap { UUID(uuidString: $0) },
            speechSnapshot: snapshot,
            rewriteSnapshot: Self.decodeSnapshot(rewriteSnapshotJson),
            lastErrorCategory: lastErrorCategory.flatMap { ErrorCategory(rawValue: $0) },
            lastErrorMessage: lastErrorMessage,
            retryCount: retryCount,
            createdAt: Self.parseDate(createdAt, "created_at"),
            updatedAt: Self.parseDate(updatedAt, "updated_at")
        )
    }
}

/// `record_attempts` 行映射。
struct DBRecordAttempt: Codable, TableRecord, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "record_attempts"

    var id: String
    var recordId: String
    var stage: String
    var attemptNo: Int
    var providerKind: String?
    var modelName: String?
    var startedAt: String
    var finishedAt: String?
    var success: Bool?
    var httpStatus: Int?
    var providerRequestId: String?
    var errorCategory: String?
    var errorMessage: String?
    var latencyMs: Int64?

    enum CodingKeys: String, CodingKey {
        case id, stage, success
        case recordId = "record_id"
        case attemptNo = "attempt_no"
        case providerKind = "provider_kind"
        case modelName = "model_name"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case httpStatus = "http_status"
        case providerRequestId = "provider_request_id"
        case errorCategory = "error_category"
        case errorMessage = "error_message"
        case latencyMs = "latency_ms"
    }
}

extension DBRecordAttempt {
    init(domain attempt: RecordAttempt) {
        id = attempt.id.uuidString.lowercased()
        recordId = attempt.recordID.uuidString.lowercased()
        stage = attempt.stage.rawValue
        attemptNo = attempt.attemptNumber
        providerKind = attempt.providerKind?.rawValue
        modelName = attempt.modelName
        startedAt = UTCTimestamp.string(from: attempt.startedAt)
        finishedAt = attempt.finishedAt.map(UTCTimestamp.string(from:))
        success = attempt.success
        httpStatus = attempt.httpStatus
        providerRequestId = attempt.providerRequestID
        errorCategory = attempt.errorCategory?.rawValue
        errorMessage = attempt.errorMessage
        latencyMs = attempt.latencyMs
    }

    func toDomain() throws -> RecordAttempt {
        guard let attemptID = UUID(uuidString: id),
              let recordID = UUID(uuidString: recordId),
              let stageValue = RecordAttempt.Stage(rawValue: stage),
              let started = UTCTimestamp.date(from: startedAt)
        else {
            throw DictationError(category: .unknown, userMessage: "尝试记录损坏", isRetryable: false)
        }
        return RecordAttempt(
            id: attemptID,
            recordID: recordID,
            stage: stageValue,
            attemptNumber: attemptNo,
            providerKind: providerKind.flatMap { ProviderProtocolKind(rawValue: $0) },
            modelName: modelName,
            startedAt: started,
            finishedAt: finishedAt.flatMap { UTCTimestamp.date(from: $0) },
            success: success,
            httpStatus: httpStatus,
            providerRequestID: providerRequestId,
            errorCategory: errorCategory.flatMap { ErrorCategory(rawValue: $0) },
            errorMessage: errorMessage,
            latencyMs: latencyMs
        )
    }
}
