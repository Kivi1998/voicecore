import Foundation
import VoiceCoreDomain

/// XCUITest 专用启动配置。
///
/// 只有测试进程显式设置 `VOICECORE_UI_TESTING=1` 时生效；每次测试使用独立的
/// Application Support 子目录，避免读取或修改用户真实数据。
struct UITestLaunchConfiguration: Sendable {
    enum Scenario: String, Sendable {
        case empty
        case historyRecord = "history-record"
        case startupError = "startup-error"
    }

    let scenario: Scenario
    let runID: String

    static var current: UITestLaunchConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICECORE_UI_TESTING"] == "1" else { return nil }
        let scenario = Scenario(rawValue: environment["VOICECORE_UI_TEST_SCENARIO"] ?? "") ?? .empty
        let runID = environment["VOICECORE_UI_TEST_RUN_ID"] ?? UUID().uuidString
        return UITestLaunchConfiguration(scenario: scenario, runID: sanitize(runID))
    }

    func dataBundleIdentifier(base: String) -> String {
        "\(base).uitest.\(runID)"
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(scalars.prefix(64))
    }
}

extension AppComposition {
    /// 写入稳定、脱敏的测试夹具；不得包含真实密钥、真实口述或用户路径。
    func prepareForUITest(_ scenario: UITestLaunchConfiguration.Scenario) async throws {
        guard scenario == .historyRecord else { return }
        let now = Date(timeIntervalSince1970: 1_786_080_000)
        guard let recordID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") else {
            throw UITestFixtureError.invalidRecordIdentifier
        }
        let snapshot = ProviderProfileSnapshot(
            profileID: nil,
            name: "测试语音模型",
            protocolKind: .openAIAudioTranscription,
            baseURL: "https://example.invalid/v1",
            modelName: "test-transcribe"
        )
        let record = DictationRecord(
            id: recordID,
            status: .completed,
            startedAt: now,
            stoppedAt: now.addingTimeInterval(5),
            completedAt: now.addingTimeInterval(6),
            durationMs: 5000,
            rawTranscript: "这是测试原始文字",
            finalText: "这是用于界面验收的测试记录",
            countUnits: 14,
            detectedLanguage: "zh-CN",
            speechSnapshot: snapshot,
            createdAt: now,
            updatedAt: now
        )
        try await records.create(record)
    }
}

private enum UITestFixtureError: Error {
    case invalidRecordIdentifier
}
