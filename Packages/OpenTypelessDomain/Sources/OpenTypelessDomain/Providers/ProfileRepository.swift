import Foundation

/// 新建或更新模型配置的输入。
///
/// 秘密字段使用可选更新语义：`nil` 表示保持原值（新建时视为未配置），
/// 显式空字符串表示清除。遮罩文本绝不能作为秘密值传入。
public struct ProviderProfileDraft: Sendable, Equatable {
    public var name: String
    public var purpose: ProviderPurpose
    public var protocolKind: ProviderProtocolKind
    public var baseURL: String
    public var modelName: String
    /// API 密钥更新：nil 保持不变，"" 清除，其他值替换。
    public var apiKeyUpdate: String?
    /// 自定义请求头整体替换；值为完整秘密，仅经专用写入方法保存。
    public var customHeadersUpdate: [String: String]?
    public var optionsJSON: String
    public var timeoutSeconds: TimeInterval
    public var isEnabled: Bool

    public init(
        name: String,
        purpose: ProviderPurpose,
        protocolKind: ProviderProtocolKind,
        baseURL: String,
        modelName: String,
        apiKeyUpdate: String? = nil,
        customHeadersUpdate: [String: String]? = nil,
        optionsJSON: String = "{}",
        timeoutSeconds: TimeInterval = 60,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.purpose = purpose
        self.protocolKind = protocolKind
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKeyUpdate = apiKeyUpdate
        self.customHeadersUpdate = customHeadersUpdate
        self.optionsJSON = optionsJSON
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
    }

    /// 格式校验（不发起网络请求）。返回用户可读错误，nil 表示合法。
    public func validationError() -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "配置名称不能为空"
        }
        if protocolKind.purpose != purpose {
            return "协议类型与配置用途不匹配"
        }
        guard let url = URL(string: baseURL), let scheme = url.scheme?.lowercased(),
              url.host != nil else {
            return "基础地址格式无效"
        }
        // 自定义地址默认仅允许 HTTPS；回环地址允许 HTTP（DEVELOPMENT §12）。
        if scheme != "https" {
            let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
            if !(scheme == "http" && isLoopback) {
                return "基础地址必须使用 HTTPS（本机回环地址可使用 HTTP）"
            }
        }
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "模型名称不能为空"
        }
        if timeoutSeconds <= 0 || timeoutSeconds > 3600 {
            return "超时时间必须在 1～3600 秒之间"
        }
        guard optionsJSON.data(using: .utf8) != nil,
              (try? JSONSerialization.jsonObject(with: Data(optionsJSON.utf8))) is [String: Any] else {
            return "扩展参数必须是 JSON 对象"
        }
        return nil
    }
}

/// 请求构建边界的受限秘密视图。
///
/// 仅模型适配器在发起请求时读取，生命周期不得超过单次请求所需范围；
/// 不得写入日志、SwiftUI 可观察状态或导出。
public struct ProviderSecrets: Sendable {
    public var profileID: UUID
    public var apiKey: String?
    public var customHeaders: [String: String]

    public init(profileID: UUID, apiKey: String?, customHeaders: [String: String]) {
        self.profileID = profileID
        self.apiKey = apiKey
        self.customHeaders = customHeaders
    }
}

/// 模型配置仓储协议。
public protocol ProviderProfileRepository: Sendable {
    /// 列出某用途全部配置（脱敏视图）。
    func list(purpose: ProviderPurpose) async throws -> [ProviderProfile]

    /// 按标识读取（脱敏视图）。
    func get(id: UUID) async throws -> ProviderProfile?

    /// 当前默认配置（脱敏视图）。
    func defaultProfile(purpose: ProviderPurpose) async throws -> ProviderProfile?

    /// 新建配置；秘密字段按草稿语义保存。返回新配置标识。
    func create(_ draft: ProviderProfileDraft) async throws -> UUID

    /// 更新配置；`draft.apiKeyUpdate` 为 nil 时保持原密钥，
    /// 空字符串显式清除，避免遮罩文本被误存为真实密钥。
    func update(id: UUID, draft: ProviderProfileDraft) async throws

    /// 设为默认：同一用途最多一个默认配置，在事务中切换。
    func setDefault(id: UUID) async throws

    /// 删除配置；被历史引用时抛出错误，调用方应提供"停用"替代。
    func delete(id: UUID) async throws

    /// 请求构建边界专用：读取完整秘密。不得用于界面展示。
    func secrets(id: UUID) async throws -> ProviderSecrets?
}

/// 应用设置键（非秘密、低频设置）。
public enum AppSettingKey: String, Codable, Sendable, CaseIterable {
    /// 全局快捷键描述。
    case shortcut
    /// 麦克风设备标识。
    case microphoneDeviceID = "microphone_device_id"
    /// 自动写入当前输入框。
    case autoInsert = "auto_insert"
    /// 恢复原剪贴板。
    case restoreClipboard = "restore_clipboard"
    /// 交互提示音。
    case interactionSound = "interaction_sound"
    /// 登录时自动启动。
    case launchAtLogin = "launch_at_login"
    /// 是否在程序坞显示。
    case showInDock = "show_in_dock"
    /// 是否启用文字改写。
    case rewriteEnabled = "rewrite_enabled"
    /// 日志级别。
    case logLevel = "log_level"
    /// 周起始日（1 = 星期一，首版默认）。
    case weekStartDay = "week_start_day"
}

/// 应用设置仓储协议。
public protocol AppSettingsRepository: Sendable {
    /// 读取 JSON 值；未设置返回 nil。
    func value(forKey key: AppSettingKey) async throws -> String?

    /// 写入 JSON 值（`value_json` 必须是合法 JSON）。
    func setValue(_ valueJSON: String, forKey key: AppSettingKey) async throws

    /// 读取布尔设置，缺省时返回默认值。
    func bool(forKey key: AppSettingKey, default defaultValue: Bool) async throws -> Bool

    /// 写入布尔设置。
    func setBool(_ value: Bool, forKey key: AppSettingKey) async throws
}
