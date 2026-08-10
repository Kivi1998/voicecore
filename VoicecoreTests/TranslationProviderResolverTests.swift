// TranslationProviderResolverTests.swift
// Provides Translation Provider Resolver Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class TranslationProviderResolverTests: XCTestCase {
    func testResolvePassesThroughConfiguredProvider() {
        let resolution = TranslationProviderResolver.resolve(
            selectedProvider: .remoteLLM,
            fallbackProvider: .customLLM,
            transcriptionEngine: .mlxAudio,
            targetLanguage: .english,
            isSelectedTextTranslation: false
        )

        XCTAssertEqual(resolution.provider, .remoteLLM)
        XCTAssertEqual(resolution.fallbackProvider, .customLLM)
    }

    func testResolvedAlwaysCollapsesToRemoteProvider() {
        XCTAssertEqual(TranslationModelProvider.resolved(rawValue: "whisperKit"), .remoteLLM)
        XCTAssertEqual(TranslationModelProvider.resolved(rawValue: nil), .remoteLLM)
    }

    func testResolvedAlwaysCollapsesToRemoteEngine() {
        XCTAssertEqual(TranscriptionEngine.resolved(rawValue: "whisperKit"), .remote)
        XCTAssertEqual(TranscriptionEngine.resolved(rawValue: nil), .remote)
    }
}
