// VoicecoreNetworkSessionTests.swift
// Provides Voicecore Network Session Tests for Voicecore test coverage.

import XCTest
@testable import Voicecore

final class VoicecoreNetworkSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoicecoreSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoicecoreSecureStorage.clearAllForTesting()
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

        VoicecoreNetworkSession.clearProcessProxyEnvironmentOverridesIfNeeded()

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
        let suiteName = "VoicecoreNetworkSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("proxy-user", forKey: AppPreferenceKey.customProxyUsername)
        defaults.set("proxy-password", forKey: AppPreferenceKey.customProxyPassword)
        VoicecoreSecureStorage.setProtectedWritesFailForTesting(true)

        VoicecoreNetworkSession.migrateLegacyProxyCredentials(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyUsername), "proxy-user")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyPassword), "proxy-password")

        VoicecoreSecureStorage.setProtectedWritesFailForTesting(false)
        VoicecoreNetworkSession.migrateLegacyProxyCredentials(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyUsername) ?? "", "")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKey.customProxyPassword) ?? "", "")
        XCTAssertEqual(VoicecoreNetworkSession.proxyCredentials(defaults: defaults).username, "proxy-user")
        XCTAssertEqual(VoicecoreNetworkSession.proxyCredentials(defaults: defaults).password, "proxy-password")
    }

    func testLegacyKeychainCleanupFailureKeepsProxyCredentialsAvailable() {
        let suiteName = "VoicecoreNetworkSessionTests.keychainCleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let usernameAccount = "network-proxy.customProxyUsername"
        let passwordAccount = "network-proxy.customProxyPassword"
        VoicecoreSecureStorage.setLegacyValueForTesting("proxy-user", for: usernameAccount)
        VoicecoreSecureStorage.setLegacyValueForTesting("proxy-password", for: passwordAccount)
        VoicecoreSecureStorage.setDeletesFailForTesting(true)

        let firstLoad = VoicecoreNetworkSession.proxyCredentials(defaults: defaults)

        XCTAssertEqual(firstLoad.username, "proxy-user")
        XCTAssertEqual(firstLoad.password, "proxy-password")
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: usernameAccount))
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: passwordAccount))
        XCTAssertTrue(VoicecoreSecureStorage.hasLegacyValueForTesting(for: usernameAccount))
        XCTAssertTrue(VoicecoreSecureStorage.hasLegacyValueForTesting(for: passwordAccount))

        VoicecoreSecureStorage.setDeletesFailForTesting(false)
        VoicecoreSecureStorage.clearCacheForTesting()

        let retriedLoad = VoicecoreNetworkSession.proxyCredentials(defaults: defaults)
        XCTAssertEqual(retriedLoad.username, "proxy-user")
        XCTAssertEqual(retriedLoad.password, "proxy-password")
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: usernameAccount))
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: passwordAccount))
    }
}
