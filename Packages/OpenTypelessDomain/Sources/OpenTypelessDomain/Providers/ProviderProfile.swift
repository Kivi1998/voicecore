import Foundation

/// 敏感值的遮罩表示。
///
/// SwiftUI 视图与可观察状态只能接触本类型，永远拿不到完整秘密；
/// 完整秘密仅在数据层专用写入方法与请求构建边界短暂存在。
public struct MaskedSecret: Codable, Sendable, Equatable {
    /// 是否已配置秘密值。
    public var hasValue: Bool
    /// 遮罩展示值，例如 `sk-••••••••abcd`；未配置时为 nil。
    public var maskedValue: String?

    public init(hasValue: Bool, maskedValue: String? = nil) {
        self.hasValue = hasValue
        self.maskedValue = maskedValue
    }

    /// 未配置秘密。
    public static let empty = MaskedSecret(hasValue: false, maskedValue: nil)

    /// 由完整秘密生成遮罩表示。
    ///
    /// 保留类似 `sk-` 的短前缀与最后 4 个字符，其余以 `•` 代替；
    /// 完整值不会出现在返回结构中。
    public static func masking(_ secret: String) -> MaskedSecret {
        guard !secret.isEmpty else { return .empty }
        let suffix = String(secret.suffix(4))
        var prefix = ""
        if let dashIndex = secret.firstIndex(of: "-"),
           secret.distance(from: secret.startIndex, to: dashIndex) <= 3
        {
            prefix = String(secret[...dashIndex])
        }
        return MaskedSecret(hasValue: true, maskedValue: "\(prefix)••••••••\(suffix)")
    }
}

/// 模型配置的脱敏领域视图。
///
/// 对应 `docs/DATA_MODEL.md` §4.3；完整 API 密钥与自定义鉴权头不出现在本类型中。
public struct ProviderProfile: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var purpose: ProviderPurpose
    public var protocolKind: ProviderProtocolKind
    /// 基础地址或完整端点；首版要求 HTTPS，回环地址允许 HTTP（由数据层校验）。
    public var baseURL: String
    public var modelName: String
    /// API 密钥遮罩。
    public var apiKey: MaskedSecret
    /// 自定义请求头；值为遮罩表示。
    public var customHeaders: [String: MaskedSecret]
    /// 协议扩展参数 JSON（白名单受控字段），不得包含秘密。
    public var optionsJSON: String
    /// 请求超时（秒）。
    public var timeoutSeconds: TimeInterval
    public var isEnabled: Bool
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        purpose: ProviderPurpose,
        protocolKind: ProviderProtocolKind,
        baseURL: String,
        modelName: String,
        apiKey: MaskedSecret = .empty,
        customHeaders: [String: MaskedSecret] = [:],
        optionsJSON: String = "{}",
        timeoutSeconds: TimeInterval = 60,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.protocolKind = protocolKind
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.optionsJSON = optionsJSON
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 历史记录保存的模型配置脱敏快照。
///
/// 删除模型配置后历史仍能说明当时使用的协议、端点和模型；
/// 绝不包含 API 密钥、完整自定义鉴权头或其他秘密。
public struct ProviderProfileSnapshot: Codable, Sendable, Equatable {
    public var profileID: UUID?
    public var name: String
    public var protocolKind: ProviderProtocolKind
    public var baseURL: String
    public var modelName: String

    public init(
        profileID: UUID?,
        name: String,
        protocolKind: ProviderProtocolKind,
        baseURL: String,
        modelName: String
    ) {
        self.profileID = profileID
        self.name = name
        self.protocolKind = protocolKind
        self.baseURL = baseURL
        self.modelName = modelName
    }
}
