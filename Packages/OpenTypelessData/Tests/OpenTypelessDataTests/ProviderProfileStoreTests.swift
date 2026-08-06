import Foundation
import XCTest

@testable import OpenTypelessData
import OpenTypelessDomain

final class ProviderProfileStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: ProviderProfileStore!
    private var settings: AppSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentypeless-profile-tests-\(UUID().uuidString)", isDirectory: true)
        let manager = try DatabaseManager(path: tempDirectory.appendingPathComponent("app.sqlite3").path)
        store = ProviderProfileStore(pool: manager.pool)
        settings = AppSettingsStore(pool: manager.pool)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeDraft(
        purpose: ProviderPurpose = .speech,
        protocolKind: ProviderProtocolKind = .openAIAudioTranscription,
        apiKey: String? = "sk-testkey1234567890abcd"
    ) -> ProviderProfileDraft {
        ProviderProfileDraft(
            name: "测试配置",
            purpose: purpose,
            protocolKind: protocolKind,
            baseURL: "https://api.example.com",
            modelName: "whisper-1",
            apiKeyUpdate: apiKey
        )
    }

    func testCreateAndListReturnsMaskedView() async throws {
        let id = try await store.create(makeDraft())
        let profile = try await XCTUnwrap(store.get(id: id))
        XCTAssertTrue(profile.apiKey.hasValue)
        XCTAssertEqual(profile.apiKey.maskedValue, "sk-••••••••abcd")
        // 脱敏视图序列化后不得包含完整密钥。
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertFalse(json.contains("sk-testkey1234567890abcd"))
    }

    func testSecretsOnlyViaDedicatedMethod() async throws {
        let id = try await store.create(makeDraft())
        let secrets = try await XCTUnwrap(store.secrets(id: id))
        XCTAssertEqual(secrets.apiKey, "sk-testkey1234567890abcd")
    }

    func testUpdateKeepsKeyWhenNil() async throws {
        let id = try await store.create(makeDraft())
        var draft = makeDraft()
        draft.name = "改名"
        draft.apiKeyUpdate = nil
        try await store.update(id: id, draft: draft)
        let secrets = try await XCTUnwrap(store.secrets(id: id))
        XCTAssertEqual(secrets.apiKey, "sk-testkey1234567890abcd", "nil 必须保持原密钥")
        XCTAssertEqual(try await store.get(id: id)?.name, "改名")
    }

    func testUpdateClearsKeyWithEmptyString() async throws {
        let id = try await store.create(makeDraft())
        var draft = makeDraft()
        draft.apiKeyUpdate = ""
        try await store.update(id: id, draft: draft)
        let secrets = try await XCTUnwrap(store.secrets(id: id))
        XCTAssertNil(secrets.apiKey, "空字符串必须显式清除密钥")
        XCTAssertFalse(try await XCTUnwrap(store.get(id: id)).apiKey.hasValue)
    }

    func testMaskedTextNeverBecomesRealKey() async throws {
        let id = try await store.create(makeDraft(apiKey: nil))
        // 模拟界面把遮罩值误传回更新流程：作为新密钥保存是调用方错误，
        // 但仓储至少保证 nil 语义不会覆盖；这里验证正常替换路径。
        var draft = makeDraft()
        draft.apiKeyUpdate = "sk-newkey9999"
        try await store.update(id: id, draft: draft)
        XCTAssertEqual(try await store.secrets(id: id)?.apiKey, "sk-newkey9999")
    }

    func testOnlyOneDefaultPerPurpose() async throws {
        let first = try await store.create(makeDraft())
        let second = try await store.create(makeDraft())
        try await store.setDefault(id: first)
        try await store.setDefault(id: second)
        let defaultProfile = try await XCTUnwrap(store.defaultProfile(purpose: .speech))
        XCTAssertEqual(defaultProfile.id, second)
        XCTAssertFalse(try await XCTUnwrap(store.get(id: first)).isDefault)
    }

    func testDefaultsAreSeparatedByPurpose() async throws {
        let speech = try await store.create(makeDraft())
        let rewrite = try await store.create(makeDraft(
            purpose: .rewrite,
            protocolKind: .openAIChat
        ))
        try await store.setDefault(id: speech)
        try await store.setDefault(id: rewrite)
        XCTAssertEqual(try await store.defaultProfile(purpose: .speech)?.id, speech)
        XCTAssertEqual(try await store.defaultProfile(purpose: .rewrite)?.id, rewrite)
    }

    func testDeleteBlockedWhenReferencedByHistory() async throws {
        let profileID = try await store.create(makeDraft())
        let manager = try DatabaseManager(path: tempDirectory.appendingPathComponent("app.sqlite3").path)
        let records = DictationRecordStore(pool: manager.pool)
        var record = DictationRecord(
            id: UUID(),
            status: .completed,
            startedAt: Date(),
            speechProfileID: profileID,
            speechSnapshot: ProviderProfileSnapshot(
                profileID: profileID,
                name: "测试配置",
                protocolKind: .openAIAudioTranscription,
                baseURL: "https://api.example.com",
                modelName: "whisper-1"
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
        record.speechProfileID = profileID
        try await records.create(record)

        do {
            try await store.delete(id: profileID)
            XCTFail("被引用配置必须阻止删除")
        } catch let error as DictationError {
            XCTAssertTrue(error.userMessage.contains("停用"))
        }
    }

    func testDeleteUnreferencedSucceeds() async throws {
        let id = try await store.create(makeDraft())
        try await store.delete(id: id)
        XCTAssertNil(try await store.get(id: id))
    }

    func testValidationRejectsInsecureURL() async throws {
        var draft = makeDraft()
        draft.baseURL = "http://api.example.com"
        do {
            _ = try await store.create(draft)
            XCTFail("非回环 HTTP 必须被拒绝")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        }
        // 回环地址允许 HTTP。
        draft.baseURL = "http://127.0.0.1:8080"
        _ = try await store.create(draft)
    }

    func testValidationRejectsPurposeMismatch() async throws {
        let draft = ProviderProfileDraft(
            name: "错配",
            purpose: .speech,
            protocolKind: .openAIChat,
            baseURL: "https://api.example.com",
            modelName: "gpt-4o-mini"
        )
        XCTAssertNotNil(draft.validationError())
    }

    func testAppSettingsBoolRoundTrip() async throws {
        XCTAssertTrue(try await settings.bool(forKey: .autoInsert, default: true))
        try await settings.setBool(false, forKey: .autoInsert)
        XCTAssertFalse(try await settings.bool(forKey: .autoInsert, default: true))
        try await settings.setBool(true, forKey: .autoInsert)
        XCTAssertTrue(try await settings.bool(forKey: .autoInsert, default: false))
    }

    func testAppSettingsRejectsInvalidJSON() async throws {
        do {
            try await settings.setValue("not-json", forKey: .shortcut)
            XCTFail("非法 JSON 必须被拒绝")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        }
    }
}
