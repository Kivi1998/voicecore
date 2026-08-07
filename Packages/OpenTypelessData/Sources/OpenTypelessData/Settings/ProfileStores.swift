import Foundation
import GRDB
import OpenTypelessDomain

/// `provider_profiles` 行映射。
struct DBProviderProfile: Codable, TableRecord, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "provider_profiles"

    var id: String
    var name: String
    var purpose: String
    var `protocol`: String
    var baseUrl: String
    var modelName: String
    var apiKey: String?
    var customHeadersJson: String
    var optionsJson: String
    var timeoutSeconds: Double
    var isEnabled: Bool
    var isDefault: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, purpose, `protocol`
        case baseUrl = "base_url"
        case modelName = "model_name"
        case apiKey = "api_key"
        case customHeadersJson = "custom_headers_json"
        case optionsJson = "options_json"
        case timeoutSeconds = "timeout_seconds"
        case isEnabled = "is_enabled"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension DBProviderProfile {
    /// 脱敏领域视图：密钥与自定义头只保留遮罩。
    func toMaskedDomain() throws -> ProviderProfile {
        guard let profileID = UUID(uuidString: id),
              let purposeValue = ProviderPurpose(rawValue: purpose),
              let protocolValue = ProviderProtocolKind(rawValue: `protocol`),
              let created = UTCTimestamp.date(from: createdAt),
              let updated = UTCTimestamp.date(from: updatedAt)
        else {
            throw DictationError(category: .unknown, userMessage: "模型配置数据损坏", isRetryable: false)
        }
        var maskedHeaders: [String: MaskedSecret] = [:]
        if let data = customHeadersJson.data(using: .utf8),
           let headers = try? JSONDecoder().decode([String: String].self, from: data)
        {
            maskedHeaders = headers.mapValues { MaskedSecret.masking($0) }
        }
        return ProviderProfile(
            id: profileID,
            name: name,
            purpose: purposeValue,
            protocolKind: protocolValue,
            baseURL: baseUrl,
            modelName: modelName,
            apiKey: apiKey.map { MaskedSecret.masking($0) } ?? .empty,
            customHeaders: maskedHeaders,
            optionsJSON: optionsJson,
            timeoutSeconds: timeoutSeconds,
            isEnabled: isEnabled,
            isDefault: isDefault,
            createdAt: created,
            updatedAt: updated
        )
    }
}

/// 模型配置仓储的 GRDB 实现。
///
/// 秘密纪律：
/// - 完整密钥只经 `secrets(id:)` 在请求构建边界读取；
/// - `update` 中 `apiKeyUpdate == nil` 保持原值，空字符串清除；
/// - 本类型任何方法都不把完整秘密写入日志。
public struct ProviderProfileStore: ProviderProfileRepository {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func list(purpose: ProviderPurpose) async throws -> [ProviderProfile] {
        try await pool.read { db in
            try DBProviderProfile
                .filter(Column("purpose") == purpose.rawValue)
                .order(Column("created_at"))
                .fetchAll(db)
                .map { try $0.toMaskedDomain() }
        }
    }

    public func get(id: UUID) async throws -> ProviderProfile? {
        let key = id.uuidString.lowercased()
        return try await pool.read { db in
            try DBProviderProfile.fetchOne(db, key: key)?.toMaskedDomain()
        }
    }

    public func defaultProfile(purpose: ProviderPurpose) async throws -> ProviderProfile? {
        try await pool.read { db in
            try DBProviderProfile
                .filter(Column("purpose") == purpose.rawValue && Column("is_default") == true)
                .fetchOne(db)?
                .toMaskedDomain()
        }
    }

    public func create(_ draft: ProviderProfileDraft) async throws -> UUID {
        if let message = draft.validationError() {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: message,
                isRetryable: false
            )
        }
        let id = UUID()
        let now = UTCTimestamp.now()
        let headersJSON = try Self.encodeHeaders(draft.customHeadersUpdate ?? [:])
        let row = DBProviderProfile(
            id: id.uuidString.lowercased(),
            name: draft.name,
            purpose: draft.purpose.rawValue,
            protocol: draft.protocolKind.rawValue,
            baseUrl: draft.baseURL,
            modelName: draft.modelName,
            apiKey: draft.apiKeyUpdate.flatMap { $0.isEmpty ? nil : $0 },
            customHeadersJson: headersJSON,
            optionsJson: draft.optionsJSON,
            timeoutSeconds: draft.timeoutSeconds,
            isEnabled: draft.isEnabled,
            isDefault: false,
            createdAt: now,
            updatedAt: now
        )
        try await pool.write { db in
            try row.insert(db)
        }
        return id
    }

    public func update(id: UUID, draft: ProviderProfileDraft) async throws {
        if let message = draft.validationError() {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: message,
                isRetryable: false
            )
        }
        let key = id.uuidString.lowercased()
        try await pool.write { db in
            guard let existing = try DBProviderProfile.fetchOne(db, key: key) else {
                throw DictationError(category: .unknown, userMessage: "配置不存在", isRetryable: false)
            }
            var updated = existing
            updated.name = draft.name
            updated.purpose = draft.purpose.rawValue
            updated.protocol = draft.protocolKind.rawValue
            updated.baseUrl = draft.baseURL
            updated.modelName = draft.modelName
            updated.optionsJson = draft.optionsJSON
            updated.timeoutSeconds = draft.timeoutSeconds
            updated.isEnabled = draft.isEnabled
            updated.updatedAt = UTCTimestamp.now()
            // 密钥专用更新语义：nil 保持，空字符串清除，其他替换。
            if let apiKeyUpdate = draft.apiKeyUpdate {
                updated.apiKey = apiKeyUpdate.isEmpty ? nil : apiKeyUpdate
            }
            if let headers = draft.customHeadersUpdate {
                updated.customHeadersJson = try Self.encodeHeaders(headers)
            }
            // 用途变化时清除默认标记，避免出现两个默认配置。
            if updated.purpose != existing.purpose {
                updated.isDefault = false
            }
            try updated.update(db)
        }
    }

    public func setDefault(id: UUID) async throws {
        let key = id.uuidString.lowercased()
        try await pool.write { db in
            guard let target = try DBProviderProfile.fetchOne(db, key: key) else {
                throw DictationError(category: .unknown, userMessage: "配置不存在", isRetryable: false)
            }
            // 同事务内先清除同用途旧默认，再设新默认。
            try db.execute(
                sql: "UPDATE provider_profiles SET is_default = 0 WHERE purpose = ? AND is_default = 1",
                arguments: [target.purpose]
            )
            try db.execute(
                sql: "UPDATE provider_profiles SET is_default = 1, updated_at = ? WHERE id = ?",
                arguments: [UTCTimestamp.now(), key]
            )
        }
    }

    public func delete(id: UUID) async throws {
        let key = id.uuidString.lowercased()
        try await pool.write { db in
            let speechRefs = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictation_records WHERE speech_profile_id = ?",
                arguments: [key]
            ) ?? 0
            let rewriteRefs = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dictation_records WHERE rewrite_profile_id = ?",
                arguments: [key]
            ) ?? 0
            guard speechRefs + rewriteRefs == 0 else {
                throw DictationError(
                    category: .configurationInvalid,
                    userMessage: "该配置已被历史记录使用，请改为停用",
                    isRetryable: false
                )
            }
            _ = try DBProviderProfile.deleteOne(db, key: key)
        }
    }

    public func secrets(id: UUID) async throws -> ProviderSecrets? {
        let key = id.uuidString.lowercased()
        return try await pool.read { db in
            guard let row = try DBProviderProfile.fetchOne(db, key: key) else { return nil }
            var headers: [String: String] = [:]
            if let data = row.customHeadersJson.data(using: .utf8) {
                headers = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            return ProviderSecrets(profileID: id, apiKey: row.apiKey, customHeaders: headers)
        }
    }

    private static func encodeHeaders(_ headers: [String: String]) throws -> String {
        try String(decoding: JSONEncoder().encode(headers), as: UTF8.self)
    }
}

/// 应用设置仓储的 GRDB 实现。
public struct AppSettingsStore: AppSettingsRepository {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func value(forKey key: AppSettingKey) async throws -> String? {
        try await pool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value_json FROM app_settings WHERE key = ?",
                arguments: [key.rawValue]
            )
        }
    }

    public func setValue(_ valueJSON: String, forKey key: AppSettingKey) async throws {
        guard (try? JSONSerialization.jsonObject(with: Data(valueJSON.utf8))) != nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "设置值必须是合法 JSON",
                isRetryable: false
            )
        }
        try await pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings (key, value_json, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                updated_at = excluded.updated_at
                """,
                arguments: [key.rawValue, valueJSON, UTCTimestamp.now()]
            )
        }
    }

    public func bool(forKey key: AppSettingKey, default defaultValue: Bool) async throws -> Bool {
        guard let raw = try await value(forKey: key) else { return defaultValue }
        return raw == "true"
    }

    public func setBool(_ value: Bool, forKey key: AppSettingKey) async throws {
        try await setValue(value ? "true" : "false", forKey: key)
    }
}
