// OnboardingSupportTests.swift
// Provides Onboarding Support Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class OnboardingSupportTests: XCTestCase {
    func testTranscriptionPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .dictation,
                muteSystemAudioWhileRecording: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testTranscriptionPermissionsIncludeSystemAudioWhenMuteEnabled() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: true
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testNonRecordingStepsDoNotRequirePermissions() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: true
        )

        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .language, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .model, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .translation, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .appEnhancement, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .finish, context: context).isEmpty)
    }

    func testRewritePermissionsIncludeScreenCaptureWhenRewriteScreenshotContextIsEnabled() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: false,
            rewriteScreenshotContextEnabled: true
        )

        XCTAssertEqual(
            OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context),
            [.screenCapture]
        )
    }

    func testFeatureSelectionResolverMapsASRSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .mlxAudio,
                remoteASRProvider: .doubaoASR
            ),
            .remoteASR(.doubaoASR)
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .remote,
                remoteASRProvider: .doubaoASR
            ),
            .remoteASR(.doubaoASR)
        )
    }

    func testFeatureSelectionResolverMapsLLMSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .local,
                localLLMRepo: "mlx-community/Qwen3-4B-4bit",
                remoteLLMProvider: .openAI
            ),
            .localLLM("mlx-community/Qwen3-4B-4bit")
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .system,
                localLLMRepo: "",
                remoteLLMProvider: .openAI
            ),
            .appleIntelligence
        )
    }

    func testFeatureSelectionResolverMigratesLegacyWhisperDirectTranslateToLocalLLM() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .remoteASR(.doubaoASR),
            existingSelection: FeatureModelSelectionID(rawValue: "whisper-direct-translate"),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .localLLM("mlx-community/Qwen3-4B-4bit"))
    }

    func testFeatureSelectionResolverPreservesExistingTranslationSelectionWhenCompatible() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .remoteASR(.doubaoASR),
            existingSelection: .remoteLLM(.openAI),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .remoteLLM(.openAI))
    }
}
