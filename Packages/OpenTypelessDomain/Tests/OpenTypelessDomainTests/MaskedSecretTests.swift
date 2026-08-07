@testable import OpenTypelessDomain
import XCTest

final class MaskedSecretTests: XCTestCase {
    func testMaskingKeepsPrefixAndSuffixOnly() {
        let masked = MaskedSecret.masking("sk-abc123def456ghi789")
        XCTAssertTrue(masked.hasValue)
        XCTAssertEqual(masked.maskedValue, "sk-••••••••i789")
    }

    func testMaskingWithoutPrefix() {
        let masked = MaskedSecret.masking("abcdefgh1234")
        XCTAssertEqual(masked.maskedValue, "••••••••1234")
    }

    func testEmptySecret() {
        let masked = MaskedSecret.masking("")
        XCTAssertFalse(masked.hasValue)
        XCTAssertNil(masked.maskedValue)
    }

    func testMaskedRepresentationNeverContainsFullSecret() throws {
        let secret = "sk-supersecretvalue-0001"
        let profile = ProviderProfile(
            id: UUID(),
            name: "测试配置",
            purpose: .speech,
            protocolKind: .openAIAudioTranscription,
            baseURL: "https://api.example.com",
            modelName: "whisper-1",
            apiKey: .masking(secret),
            createdAt: Date(),
            updatedAt: Date()
        )
        let data = try JSONEncoder().encode(profile)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains(secret))
    }

    func testSnapshotContainsNoSecretFields() throws {
        let snapshot = ProviderProfileSnapshot(
            profileID: UUID(),
            name: "快照",
            protocolKind: .openAIChat,
            baseURL: "https://api.example.com",
            modelName: "gpt-4o-mini"
        )
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("customHeaders"))
    }
}
