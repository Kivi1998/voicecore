// AppUpdateManagerTests.swift
// Provides App Update Manager Tests for Voicecore test coverage.

import XCTest
@testable import Voicecore

final class AppUpdateManagerTests: XCTestCase {
    @MainActor
    func testSelectedFeedURLStringDefaultsToStableFeed() {
        let url = AppUpdateManager.selectedFeedURLString(
            betaUpdatesEnabled: false,
            interfaceLanguage: .english,
            environment: [:]
        )

        XCTAssertTrue(url.hasPrefix("https://voicecore.actnow.dev/updates/stable/appcast.xml"))
        XCTAssertEqual(URLComponents(string: url)?.queryItems?.first(where: { $0.name == "lang" })?.value, "en")
    }

    @MainActor
    func testSelectedFeedURLStringUsesBetaFeedWhenPreferenceIsEnabled() {
        let url = AppUpdateManager.selectedFeedURLString(
            betaUpdatesEnabled: true,
            interfaceLanguage: .chineseSimplified,
            environment: [:]
        )

        XCTAssertTrue(url.hasPrefix("https://voicecore.actnow.dev/updates/beta/appcast.xml"))
        XCTAssertEqual(URLComponents(string: url)?.queryItems?.first(where: { $0.name == "lang" })?.value, "zh-Hans")
    }

    @MainActor
    func testEnvironmentCanForceStableFeedForDevelopment() {
        let url = AppUpdateManager.selectedFeedURLString(
            betaUpdatesEnabled: true,
            interfaceLanguage: .japanese,
            environment: ["VOICECORE_UPDATE_CHANNEL": "stable"]
        )

        XCTAssertTrue(url.hasPrefix("https://voicecore.actnow.dev/updates/stable/appcast.xml"))
        XCTAssertEqual(URLComponents(string: url)?.queryItems?.first(where: { $0.name == "lang" })?.value, "ja")
    }

    @MainActor
    func testEnvironmentCanForceBetaFeedWhenExplicitlyEnabledForDevelopment() {
        let url = AppUpdateManager.selectedFeedURLString(
            betaUpdatesEnabled: false,
            interfaceLanguage: .english,
            environment: [
                "VOICECORE_UPDATE_CHANNEL": "beta",
                "VOICECORE_ENABLE_BETA_UPDATES": "true"
            ]
        )

        XCTAssertTrue(url.hasPrefix("https://voicecore.actnow.dev/updates/beta/appcast.xml"))
        XCTAssertEqual(URLComponents(string: url)?.queryItems?.first(where: { $0.name == "lang" })?.value, "en")
    }

    @MainActor
    func testBetaUpdatesPreferenceChangeClearsExistingUpdateState() {
        let manager = AppUpdateManager(defaults: TestDoubles.makeUserDefaults())
        manager.setUpdateStateForTesting(
            hasUpdate: true,
            latestVersion: "1.4.0-beta.1 (1004001)",
            issue: "Previous channel issue"
        )

        manager.betaUpdatesPreferenceDidChange()

        XCTAssertFalse(manager.hasUpdate)
        XCTAssertNil(manager.latestVersion)
        XCTAssertNil(manager.updateCheckIssueMessage)
    }

    @MainActor
    func testLocalizedFeedURLStringUsesInterfaceLanguageQueryParameter() {
        let url = AppUpdateManager.localizedFeedURLString(
            baseURLString: "https://voicecore.actnow.dev/updates/stable/appcast.xml",
            interfaceLanguage: .chineseSimplified
        )

        let components = URLComponents(string: url)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "lang" })?.value, "zh-Hans")
    }

    @MainActor
    func testLocalizedFeedURLStringPreservesExistingQueryItems() {
        let url = AppUpdateManager.localizedFeedURLString(
            baseURLString: "https://voicecore.actnow.dev/updates/stable/appcast.xml?channel=stable",
            interfaceLanguage: .japanese
        )

        let components = URLComponents(string: url)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "channel" })?.value, "stable")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "lang" })?.value, "ja")
    }

    @MainActor
    func testUpdateRequestHeadersIncludeAcceptLanguageWithFallbacks() {
        let headers = AppUpdateManager.updateRequestHeaders(interfaceLanguage: .chineseSimplified)

        XCTAssertEqual(headers["Accept-Language"], "zh-Hans, zh;q=0.9, en;q=0.8")
    }

    @MainActor
    func testUpdateRequestHeadersDoNotDuplicateEnglishFallback() {
        let headers = AppUpdateManager.updateRequestHeaders(interfaceLanguage: .english)

        XCTAssertEqual(headers["Accept-Language"], "en")
    }

    @MainActor
    func testSparkleIsDisabledForDevelopmentAndTestHostBundles() {
        XCTAssertFalse(AppUpdateManager.shouldEnableSparkle(bundleIdentifier: "com.kivi.voicecore.Voicecore.dev"))
        XCTAssertFalse(AppUpdateManager.shouldEnableSparkle(bundleIdentifier: "com.kivi.voicecore.Voicecore.testhost"))
        XCTAssertFalse(AppUpdateManager.shouldEnableSparkle(bundleIdentifier: "com.kivi.voicecore.Voicecore.local"))
        XCTAssertFalse(AppUpdateManager.shouldEnableSparkle(bundleIdentifier: "com.kivi.Voicecore"))
    }

    @MainActor
    func testSparkleIsEnabledForReleaseBundle() {
        XCTAssertTrue(AppUpdateManager.shouldEnableSparkle(bundleIdentifier: "com.kivi.voicecore.Voicecore"))
    }
}
