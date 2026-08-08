// VoicecoreSecureStorageTests.swift
// Verifies Data Protection Keychain migration behavior without touching the user's keychain.

import XCTest
import Security
@testable import Voicecore

final class VoicecoreSecureStorageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoicecoreSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoicecoreSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testLegacyValueMigratesOnlyAfterProtectedWriteSucceeds() {
        let account = "remote-provider.doubaoASR.credentials"
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testFailedProtectedWriteKeepsLegacyValueAvailableForCurrentRequest() {
        let account = "remote-provider.doubaoASR.credentials"
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoicecoreSecureStorage.setProtectedWritesFailForTesting(true)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertFalse(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))

        VoicecoreSecureStorage.clearCacheForTesting()
        VoicecoreSecureStorage.setProtectedWritesFailForTesting(false)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testFailedLegacyCleanupReturnsProtectedValueAndRetriesLater() {
        let account = "remote-provider.doubaoASR.credentials"
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoicecoreSecureStorage.setDeletesFailForTesting(true)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))

        VoicecoreSecureStorage.clearCacheForTesting()
        VoicecoreSecureStorage.setDeletesFailForTesting(false)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testProtectedValueTakesPrecedenceAndCleansUpLegacyValue() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoicecoreSecureStorage.set("current-secret", for: account))
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        XCTAssertEqual(VoicecoreSecureStorage.string(for: account), "current-secret")
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testRemovingValueClearsProtectedAndLegacyCopies() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoicecoreSecureStorage.set("current-secret", for: account))
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        VoicecoreSecureStorage.removeValue(for: account)

        XCTAssertNil(VoicecoreSecureStorage.string(for: account))
        XCTAssertFalse(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testRemovingValueReportsFailureAndPreservesStoredCopies() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoicecoreSecureStorage.set("current-secret", for: account))
        VoicecoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoicecoreSecureStorage.setDeletesFailForTesting(true)

        XCTAssertFalse(VoicecoreSecureStorage.removeValue(for: account))

        XCTAssertTrue(VoicecoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoicecoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testLegacyQueryExplicitlyExcludesDataProtectionKeychain() {
        let query = VoicecoreSecureStorage.legacyQuery(
            for: "remote-provider.doubaoASR.credentials",
            interactionAllowed: false
        )

        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, false)
    }
}
