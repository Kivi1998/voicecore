import Foundation

/// 标准错误类别。
///
/// 取值与 `docs/DATA_MODEL.md` §3.4 一一对应；用户可见信息必须脱敏，
/// 禁止只保存一段无法分类的错误字符串。
public enum ErrorCategory: String, Codable, Sendable, CaseIterable {
    case permissionDenied = "permission_denied"
    case deviceUnavailable = "device_unavailable"
    case audioWriteFailed = "audio_write_failed"
    case audioInvalid = "audio_invalid"
    case configurationInvalid = "configuration_invalid"
    case authenticationFailed = "authentication_failed"
    case rateLimited = "rate_limited"
    case networkUnavailable = "network_unavailable"
    case providerTimeout = "provider_timeout"
    case providerRejected = "provider_rejected"
    case providerBadResponse = "provider_bad_response"
    case rewriteFailed = "rewrite_failed"
    case injectionPermissionDenied = "injection_permission_denied"
    case injectionTargetUnavailable = "injection_target_unavailable"
    case appInterrupted = "app_interrupted"
    case unknown

    /// 默认是否允许用户重试（自动重试策略由提供商适配层按协议规范另行限制）。
    public var isRetryableByUser: Bool {
        switch self {
        case .permissionDenied, .configurationInvalid, .injectionPermissionDenied:
            false
        default:
            true
        }
    }
}

/// 已脱敏的领域错误。
///
/// `userMessage` 面向用户且不得包含密钥、鉴权头、完整音频或完整口述内容。
public struct DictationError: Codable, Sendable, Equatable {
    public var category: ErrorCategory
    public var userMessage: String
    public var isRetryable: Bool
    public var occurredAt: Date

    public init(
        category: ErrorCategory,
        userMessage: String,
        isRetryable: Bool? = nil,
        occurredAt: Date = Date()
    ) {
        self.category = category
        self.userMessage = userMessage
        self.isRetryable = isRetryable ?? category.isRetryableByUser
        self.occurredAt = occurredAt
    }
}

extension DictationError: Error {}
