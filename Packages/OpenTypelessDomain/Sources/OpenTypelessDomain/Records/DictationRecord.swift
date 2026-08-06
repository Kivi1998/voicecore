import Foundation

/// 口述记录领域实体。
///
/// 对应 `docs/DATA_MODEL.md` §4.1。时间为 UTC `Date`，展示层负责本地时区格式化；
/// 录音路径为相对录音根目录的稳定路径，不保存平台绝对路径。
public struct DictationRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var status: DictationStatus
    /// 开始录音时间（UTC）。
    public var startedAt: Date
    /// 用户停止或采集结束时间。
    public var stoppedAt: Date?
    /// 全流程完成时间。
    public var completedAt: Date?
    /// 录音时长（毫秒）。
    public var durationMs: Int64
    /// 相对录音根目录路径，例如 `2026/08/06/<record-id>.m4a`。
    public var audioRelativePath: String?
    public var audioMimeType: String?
    public var audioSizeBytes: Int64?
    /// 完整性校验，可异步生成。
    public var audioSHA256: String?
    /// 语音识别原文。
    public var rawTranscript: String?
    /// 最终使用文字。
    public var finalText: String?
    /// 统计单位数（在最终文字保存时写入）。
    public var countUnits: Int64
    public var detectedLanguage: String?
    public var isFavorite: Bool
    public var speechProfileID: UUID?
    public var rewriteProfileID: UUID?
    /// 当次语音配置脱敏快照。
    public var speechSnapshot: ProviderProfileSnapshot
    /// 当次改写配置脱敏快照；关闭改写时为 nil。
    public var rewriteSnapshot: ProviderProfileSnapshot?
    public var lastErrorCategory: ErrorCategory?
    /// 用户可理解且已脱敏的错误信息。
    public var lastErrorMessage: String?
    public var retryCount: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        status: DictationStatus,
        startedAt: Date,
        stoppedAt: Date? = nil,
        completedAt: Date? = nil,
        durationMs: Int64 = 0,
        audioRelativePath: String? = nil,
        audioMimeType: String? = nil,
        audioSizeBytes: Int64? = nil,
        audioSHA256: String? = nil,
        rawTranscript: String? = nil,
        finalText: String? = nil,
        countUnits: Int64 = 0,
        detectedLanguage: String? = nil,
        isFavorite: Bool = false,
        speechProfileID: UUID? = nil,
        rewriteProfileID: UUID? = nil,
        speechSnapshot: ProviderProfileSnapshot,
        rewriteSnapshot: ProviderProfileSnapshot? = nil,
        lastErrorCategory: ErrorCategory? = nil,
        lastErrorMessage: String? = nil,
        retryCount: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.status = status
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.audioRelativePath = audioRelativePath
        self.audioMimeType = audioMimeType
        self.audioSizeBytes = audioSizeBytes
        self.audioSHA256 = audioSHA256
        self.rawTranscript = rawTranscript
        self.finalText = finalText
        self.countUnits = countUnits
        self.detectedLanguage = detectedLanguage
        self.isFavorite = isFavorite
        self.speechProfileID = speechProfileID
        self.rewriteProfileID = rewriteProfileID
        self.speechSnapshot = speechSnapshot
        self.rewriteSnapshot = rewriteSnapshot
        self.lastErrorCategory = lastErrorCategory
        self.lastErrorMessage = lastErrorMessage
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 单次转录、改写或输入尝试，用于诊断与审查。
///
/// 对应 `docs/DATA_MODEL.md` §4.2；不得保存请求正文、鉴权头、
/// 完整供应商响应或用户音频。
public struct RecordAttempt: Identifiable, Codable, Sendable, Equatable {
    /// 尝试阶段。
    public enum Stage: String, Codable, Sendable, CaseIterable {
        case transcription
        case rewrite
        case injection
    }

    public var id: UUID
    public var recordID: UUID
    public var stage: Stage
    /// 同阶段从 1 开始。
    public var attemptNumber: Int
    public var providerKind: ProviderProtocolKind?
    public var modelName: String?
    public var startedAt: Date
    public var finishedAt: Date?
    /// 完成前为 nil。
    public var success: Bool?
    public var httpStatus: Int?
    /// 供应商请求标识。
    public var providerRequestID: String?
    public var errorCategory: ErrorCategory?
    /// 已脱敏错误信息。
    public var errorMessage: String?
    public var latencyMs: Int64?

    public init(
        id: UUID,
        recordID: UUID,
        stage: Stage,
        attemptNumber: Int,
        providerKind: ProviderProtocolKind? = nil,
        modelName: String? = nil,
        startedAt: Date,
        finishedAt: Date? = nil,
        success: Bool? = nil,
        httpStatus: Int? = nil,
        providerRequestID: String? = nil,
        errorCategory: ErrorCategory? = nil,
        errorMessage: String? = nil,
        latencyMs: Int64? = nil
    ) {
        self.id = id
        self.recordID = recordID
        self.stage = stage
        self.attemptNumber = attemptNumber
        self.providerKind = providerKind
        self.modelName = modelName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.success = success
        self.httpStatus = httpStatus
        self.providerRequestID = providerRequestID
        self.errorCategory = errorCategory
        self.errorMessage = errorMessage
        self.latencyMs = latencyMs
    }
}
