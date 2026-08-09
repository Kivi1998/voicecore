// VoiceCoreSecureStorageTests.swift
// Verifies Data Protection Keychain migration behavior without touching the user's keychain.

import XCTest
import Security
@testable import Voicecore

final class VoiceCoreSecureStorageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoiceCoreSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoiceCoreSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testLegacyValueMigratesOnlyAfterProtectedWriteSucceeds() {
        let account = "remote-provider.doubaoASR.credentials"
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testFailedProtectedWriteKeepsLegacyValueAvailableForCurrentRequest() {
        let account = "remote-provider.doubaoASR.credentials"
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoiceCoreSecureStorage.setProtectedWritesFailForTesting(true)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertFalse(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))

        VoiceCoreSecureStorage.clearCacheForTesting()
        VoiceCoreSecureStorage.setProtectedWritesFailForTesting(false)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testFailedLegacyCleanupReturnsProtectedValueAndRetriesLater() {
        let account = "remote-provider.doubaoASR.credentials"
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoiceCoreSecureStorage.setDeletesFailForTesting(true)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))

        VoiceCoreSecureStorage.clearCacheForTesting()
        VoiceCoreSecureStorage.setDeletesFailForTesting(false)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "legacy-secret")
        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testProtectedValueTakesPrecedenceAndCleansUpLegacyValue() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoiceCoreSecureStorage.set("current-secret", for: account))
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        XCTAssertEqual(VoiceCoreSecureStorage.string(for: account), "current-secret")
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testRemovingValueClearsProtectedAndLegacyCopies() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoiceCoreSecureStorage.set("current-secret", for: account))
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)

        VoiceCoreSecureStorage.removeValue(for: account)

        XCTAssertNil(VoiceCoreSecureStorage.string(for: account))
        XCTAssertFalse(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertFalse(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testRemovingValueReportsFailureAndPreservesStoredCopies() {
        let account = "remote-provider.doubaoASR.credentials"
        XCTAssertTrue(VoiceCoreSecureStorage.set("current-secret", for: account))
        VoiceCoreSecureStorage.setLegacyValueForTesting("legacy-secret", for: account)
        VoiceCoreSecureStorage.setDeletesFailForTesting(true)

        XCTAssertFalse(VoiceCoreSecureStorage.removeValue(for: account))

        XCTAssertTrue(VoiceCoreSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoiceCoreSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testLegacyQueryExplicitlyExcludesDataProtectionKeychain() {
        let query = VoiceCoreSecureStorage.legacyQuery(
            for: "remote-provider.doubaoASR.credentials",
            interactionAllowed: false
        )

        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, false)
    }
}
