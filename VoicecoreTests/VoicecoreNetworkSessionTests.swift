// VoiceCoreNetworkSessionTests.swift
// Provides VoiceCore Network Session Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class VoiceCoreNetworkSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoiceCoreSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoiceCoreSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testClearProcessProxyEnvironmentOverridesRemovesStandardProxyVariables() {
        let keys = [
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "NO_PROXY"
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, ProcessInfo.processInfo.environment[key])
        })

        setenv("http_proxy", "http://127.0.0.1:7897", 1)
        setenv("https_proxy", "http://127.0.0.1:7897", 1)
        setenv("all_proxy", "socks5://127.0.0.1:7897", 1)
        setenv("no_proxy", "localhost,127.0.0.1", 1)

        VoiceCoreNetworkSession.clearProcessProxyEnvironmentOverridesIfNeeded()

        XCTAssertNil(ProcessInfo.processInfo.environment["http_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["https_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["all_proxy"])
        XCTAssertNil(ProcessInfo.processInfo.environment["no_proxy"])

        for (key, value) in originalValues {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }

    func testLegacyProxyMigrationKeepsDefaultsWhenProtectedWriteFails() {
        let suiteName = "VoiceCoreNetworkSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("proxy-user", forKey: AppPreferenceKey.customProxyUsername)
        defaults.set("proxy-password", forKey: AppPreferenceKey.customProxyPassword)
        VoiceCoreSecureStorage.setProtectedWritesFailForTesting(true)

        VoiceCoreNetworkSession.migrateLegacyProxyCredentials(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyUsername), "proxy-user")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyPassword), "proxy-password")

        VoiceCoreSecureStorage.setProtectedWritesFailForTesting(false)
        VoiceCoreNetworkSession.migrateLegacyProxyCredentials(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyUsername) ?? "", "")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyPassword) ?? "", "")
        XCTAssertEqual(VoiceCoreNetworkSession.proxyCredentials(defaults: defaults).username, "proxy-user")
        XCTAssertEqual(VoiceCoreNetworkSession.proxyCredentials(defaults: defaults).password, "proxy-password")
    }

    func testLegacyKeychainCleanupFailureKeepsProxyCredentialsAvailable() {
        let suiteName = "VoiceCoreNetworkSessionTests.keychainCleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let usernameAccount = "network-proxy.customProxyUsername"
        let passwordAccount = "network-proxy.customProxyPassword"
        VoiceCoreSecureStorage.setLegacyValueForTesting("proxy-user", for: usernameAccount)
        VoiceCoreSecureStorage.setLegacyValueForTesting("proxy-password", for: passwordAccount)
        VoiceCoreSecureStorage.setDeletesFailForTesting(true)

        let firstLoad = VoiceCoreNetworkSession.proxyCredentials(defaults: defaults)

        XCTAssertEqual(firstLoad.username, "proxy-user")
        XCTAssertEqual(firstLoad.password, "proxy-password")
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: usernameAccount))
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: passwordAccount))
        XCTAssertTrue(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: usernameAccount))
        XCTAssertTrue(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: passwordAccount))

        VoiceCoreSecureStorage.setDeletesFailForTesting(false)
        VoiceCoreSecureStorage.clearCacheForTesting()

        let retriedLoad = VoiceCoreNetworkSession.proxyCredentials(defaults: defaults)
        XCTAssertEqual(retriedLoad.username, "proxy-user")
        XCTAssertEqual(retriedLoad.password, "proxy-password")
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: usernameAccount))
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: passwordAccount))
    }
}
