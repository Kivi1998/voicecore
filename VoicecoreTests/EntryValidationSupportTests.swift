// EntryValidationSupportTests.swift
// Provides Entry Validation Support Tests for VoiceCore test coverage.

import XCTest
@testable import Voicecore

final class EntryValidationSupportTests: XCTestCase {
    func testPrepareAllowsDuplicateNormalizedHotwordTerm() throws {
        let existingEntry = TestFactories.makeEntry(term: "VoiceCore")

        XCTAssertNoThrow(
            try DictionaryEntryInputPreparer.prepare(
                term: "voicecore",
                replacementTerms: [],
                groupID: nil,
                entries: [existingEntry]
            )
        )
    }

    func testPrepareRejectsReplacementMatchingExistingHotwordTerm() throws {
        let existingEntry = TestFactories.makeEntry(term: "VoiceCore")

        XCTAssertThrowsError(
            try DictionaryEntryInputPreparer.prepare(
                term: "Voice Input",
                replacementTerms: ["voicecore"],
                groupID: nil,
                entries: [existingEntry]
            )
        ) { error in
            guard case DictionaryStoreError.duplicateReplacementTerm("voicecore") = error else {
                return XCTFail("Expected duplicateReplacementTerm, got \(error)")
            }
        }
    }
}
