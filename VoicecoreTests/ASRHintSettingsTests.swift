// ASRHintSettingsTests.swift
// Provides ASRHint Settings Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

@MainActor
final class ASRHintSettingsTests: XCTestCase {
    func testLoadSanitizesUnsupportedPromptEditors() {
        let raw = """
        {"mlxAudio":{"followsUserMainLanguage":true,"promptTemplate":"  should be removed  "},"openAIWhisper":{"followsUserMainLanguage":false,"promptTemplate":"  Bias {{USER_MAIN_LANGUAGE}}  "}}
        """

        let loaded = ASRHintSettingsStore.load(from: raw)

        XCTAssertEqual(
            loaded[.mlxAudio]?.promptTemplate,
            ""
        )
        XCTAssertEqual(loaded[.openAIWhisper]?.promptTemplate, "Bias {{USER_MAIN_LANGUAGE}}")
    }

    func testResolvedSettingsFallsBackToDefaults() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .glmASR, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, AppPromptDefaults.text(for: .glmASRHint))
        XCTAssertEqual(settings.promptTemplate, AppPreferenceKey.asrDictionaryTermsTemplateVariable)
    }

    func testResolveOpenAIUsesBaseLanguageAndResolvedPrompt() {
        let payload = ASRHintResolver.resolve(
            target: .openAIWhisper,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Primary {{USER_MAIN_LANGUAGE}}"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.prompt, "Primary Traditional Chinese")
    }

    func testResolveMLXAvoidsPromptBiasAndForcedLanguage() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: "Bias {{USER_MAIN_LANGUAGE}} punctuation"
            ),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertNil(payload.language)
        XCTAssertNil(payload.prompt)
    }

    func testResolvedMLXSettingsDefaultToEmptyPrompt() {
        let settings = ASRHintSettingsStore.resolvedSettings(for: .mlxAudio, rawValue: nil)

        XCTAssertTrue(settings.followsUserMainLanguage)
        XCTAssertEqual(settings.promptTemplate, "")
    }

    func testDefaultASRPromptResolvesToDictionaryTermsOnly() {
        let payload = ASRHintResolver.resolve(
            target: .openAIWhisper,
            settings: ASRHintSettingsStore.resolvedSettings(for: .openAIWhisper, rawValue: nil),
            userLanguageCodes: ["zh-Hans", "en"],
            dictionaryTerms: "Codex\nVoiceCore"
        )

        XCTAssertEqual(payload.language, nil)
        XCTAssertEqual(payload.prompt, "Codex\nVoiceCore")
    }

    func testDefaultASRPromptDoesNotAutoAppendLanguageContext() {
        let payload = ASRHintResolver.resolve(
            target: .glmASR,
            settings: ASRHintSettings(
                followsUserMainLanguage: true,
                promptTemplate: ""
            ),
            userLanguageCodes: ["zh-Hans", "en"],
            dictionaryTerms: ""
        )

        XCTAssertNil(payload.prompt)
    }

    func testResolveDoubaoUsesVariantMappingForTraditionalChinese() {
        let payload = ASRHintResolver.resolve(
            target: .doubaoASR,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(payload.language, "zh-CN")
        XCTAssertEqual(payload.chineseOutputVariant, "zh-Hant")
        XCTAssertNil(payload.prompt)
    }

    func testResolveAliyunDeduplicatesAndLimitsLanguageHints() {
        let payload = ASRHintResolver.resolve(
            target: .aliyunBailianASR,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hans", "en", "zh-Hant", "ja", "ko"]
        )

        XCTAssertEqual(payload.languageHints, ["zh", "en", "ja"])
        XCTAssertEqual(payload.language, "zh")
    }

    func testResolveAliyunBuildsHotwordsFromContextAndDictionaryTerms() {
        let payload = ASRHintResolver.resolve(
            target: .aliyunBailianASR,
            settings: ASRHintSettings(contextualPhrasesText: "VoiceCore\nFireRed\nVoiceCore"),
            userLanguageCodes: ["zh-Hans"],
            dictionaryTerms: "Codex\nFireRed"
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.contextualPhrases, ["VoiceCore", "FireRed", "Codex"])
    }

    func testResolveStepFunBuildsPromptFromTerms() {
        let payload = ASRHintResolver.resolve(
            target: .stepFunASR,
            settings: ASRHintSettings(contextualPhrasesText: "VoiceCore\nFireRed\nVoiceCore"),
            userLanguageCodes: ["zh-Hans"],
            dictionaryTerms: "Codex\nFireRed"
        )

        XCTAssertEqual(payload.language, "zh")
        XCTAssertEqual(payload.contextualPhrases, ["VoiceCore", "FireRed", "Codex"])
        XCTAssertNotNil(payload.prompt)
        XCTAssertContains(payload.prompt ?? "", "Preserve names")
        XCTAssertContains(payload.prompt ?? "", "VoiceCore")
        XCTAssertContains(payload.prompt ?? "", "FireRed")
        XCTAssertContains(payload.prompt ?? "", "Codex")
        XCTAssertEqual(payload.prompt?.components(separatedBy: "VoiceCore").count, 2)
        XCTAssertEqual(payload.prompt?.components(separatedBy: "FireRed").count, 2)
    }

    func testResolveMLXUsesPromptNameForQwenModel() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"],
            mlxModelRepo: "mlx-community/Qwen3-ASR"
        )

        XCTAssertEqual(payload.language, "Traditional Chinese")
    }

    func testResolveMLXKeepsQwenPrimaryLanguageWhenSecondaryLanguagesAreConfigured() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hans", "en"],
            mlxModelRepo: "mlx-community/Qwen3-ASR-0.6B-4bit"
        )

        XCTAssertEqual(payload.language, "Simplified Chinese")
        XCTAssertEqual(payload.otherLanguages, ["English"])
    }

    func testResolveMLXAllowsQwenAutomaticLanguageWhenFollowingMainLanguageIsDisabled() {
        let payload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(followsUserMainLanguage: false),
            userLanguageCodes: ["zh-Hans", "en"],
            mlxModelRepo: "mlx-community/Qwen3-ASR-0.6B-4bit"
        )

        XCTAssertNil(payload.language)
    }

    func testResolveMLXUsesSenseVoiceLanguageRoutingOnlyForSupportedLocales() {
        let cantonesePayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["yue"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertEqual(cantonesePayload.language, "yue")

        let chinesePayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertEqual(chinesePayload.language, "zh")

        let unsupportedPayload = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["fr"],
            mlxModelRepo: "mlx-community/SenseVoiceSmall"
        )
        XCTAssertNil(unsupportedPayload.language)
    }

    func testResolveMLXUsesCapabilityLanguageRouting() {
        let unsupportedQwen = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["sw"],
            mlxModelRepo: "mlx-community/Qwen3-ASR-0.6B-4bit"
        )
        XCTAssertNil(unsupportedQwen.language)

        let automaticParakeet = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["de"],
            mlxModelRepo: "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertNil(automaticParakeet.language)

        let nemotron = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hans", "en"],
            mlxModelRepo: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
        )
        XCTAssertEqual(nemotron.language, "zh-CN")

        let traditionalChineseNemotron = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hant"],
            mlxModelRepo: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"
        )
        XCTAssertEqual(traditionalChineseNemotron.language, "zh-TW")

        let automaticVoxtral = ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: ASRHintSettings(),
            userLanguageCodes: ["zh-Hans"],
            mlxModelRepo: "mlx-community/Voxtral-Mini-4B-Realtime-6bit"
        )
        XCTAssertNil(automaticVoxtral.language)
    }

    func testResolveDictationSettingsUsesMainLanguageAndContextualPhrases() {
        let settings = ASRHintSettings(
            followsUserMainLanguage: true,
            contextualPhrasesText: "VoiceCore\nFireRed\n VoiceCore \n",
            prefersOnDeviceRecognition: true,
            addsPunctuation: false,
            reportsPartialResults: false
        )

        let resolved = ASRHintResolver.resolveDictationSettings(
            settings: settings,
            userLanguageCodes: ["zh-Hant"]
        )

        XCTAssertEqual(resolved.localeIdentifier, "zh-TW")
        XCTAssertEqual(resolved.contextualPhrases, ["VoiceCore", "FireRed", "VoiceCore"])
        XCTAssertTrue(resolved.prefersOnDeviceRecognition)
        XCTAssertFalse(resolved.addsPunctuation)
        XCTAssertFalse(resolved.reportsPartialResults)
    }

    func testSanitizedDictationContextualPhrasesTrimBlankLines() {
        let settings = ASRHintSettingsStore.sanitized(
            ASRHintSettings(
                contextualPhrasesText: "\n  VoiceCore  \n\n FireRed ASR \n"
            ),
            for: .dictation
        )

        XCTAssertEqual(settings.contextualPhrasesText, "VoiceCore\nFireRed ASR")
    }

    func testLanguageSummaryAndOutputVariantDescription() {
        XCTAssertEqual(
            ASRHintResolver.selectedLanguageSummary(["zh-Hans", "en"]),
            "Simplified Chinese, English"
        )
        XCTAssertEqual(
            ASRHintResolver.outputVariantDescription(for: UserMainLanguageOption.option(for: "zh-hant")!),
            AppLocalization.localizedString("Traditional Chinese")
        )
    }
}
