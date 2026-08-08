// EntryValidationSupportTests.swift
// Provides Entry Validation Support Tests for Voicecore test coverage.

import XCTest
@testable import Voicecore

final class EntryValidationSupportTests: XCTestCase {
    func testPrepareAllowsDuplicateNormalizedHotwordTerm() throws {
        let existingEntry = TestFactories.makeEntry(term: "Voicecore")

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
        let existingEntry = TestFactories.makeEntry(term: "Voicecore")

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
