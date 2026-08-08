@testable import Voicecore
import XCTest

@MainActor
final class APIOnlyModeTests: XCTestCase {
    func testOnlyRemoteTranscriptionEngineIsExposed() {
        XCTAssertEqual(TranscriptionEngine.allCases, [.remote])
        XCTAssertEqual(TranscriptionEngine.resolved(rawValue: nil), .remote)
        XCTAssertEqual(TranscriptionEngine.resolved(rawValue: "mlxAudio"), .remote)
        XCTAssertEqual(TranscriptionEngine.resolved(rawValue: "sherpaOnnx"), .remote)
    }

    func testOnlyRemoteTextProvidersAreExposed() {
        XCTAssertEqual(EnhancementMode.allCases, [.off, .remoteLLM])
        XCTAssertEqual(TranslationModelProvider.allCases, [.remoteLLM])
        XCTAssertEqual(RewriteModelProvider.allCases, [.remoteLLM])
        XCTAssertEqual(TranslationModelProvider.resolved(rawValue: "customLLM"), .remoteLLM)
        XCTAssertEqual(TranslationModelProvider.resolved(rawValue: "localGGUF"), .remoteLLM)
    }

    func testExistingLocalSelectionsMigrateToSelectedAPIs() throws {
        let suiteName = "APIOnlyModeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(RemoteASRProvider.doubaoASR.rawValue, forKey: AppPreferenceKey.remoteASRSelectedProvider)
        defaults.set(RemoteLLMProvider.openAI.rawValue, forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        defaults.set(TranscriptionEngine.mlxAudio.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        defaults.set(TranslationModelProvider.localGGUF.rawValue, forKey: AppPreferenceKey.translationModelProvider)
        defaults.set(RewriteModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)

        FeatureSettingsStore.migrateIfNeeded(defaults: defaults)
        FeatureSettingsStore.enforceRemoteAPIOnly(defaults: defaults)

        let settings = FeatureSettingsStore.load(defaults: defaults)
        let remoteASR = FeatureModelSelectionID.remoteASR(.doubaoASR)
        let remoteLLM = FeatureModelSelectionID.remoteLLM(.openAI)

        XCTAssertEqual(settings.transcription.asrSelectionID, remoteASR)
        XCTAssertEqual(settings.translation.asrSelectionID, remoteASR)
        XCTAssertEqual(settings.rewrite.asrSelectionID, remoteASR)
        XCTAssertEqual(settings.meeting.asrSelectionID, remoteASR)
        XCTAssertEqual(settings.transcription.llmSelectionID, remoteLLM)
        XCTAssertEqual(settings.transcription.notes.titleModelSelectionID, remoteLLM)
        XCTAssertEqual(settings.translation.modelSelectionID, remoteLLM)
        XCTAssertEqual(settings.rewrite.llmSelectionID, remoteLLM)
        XCTAssertEqual(settings.meeting.summaryModelSelectionID, remoteLLM)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.transcriptionEngine), TranscriptionEngine.remote.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.translationModelProvider), TranslationModelProvider.remoteLLM.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.rewriteModelProvider), RewriteModelProvider.remoteLLM.rawValue)
    }
}
