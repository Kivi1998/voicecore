// TestDoubles.swift
// Provides Test Doubles for test support.

import Foundation
import XCTest
@testable import Voicecore

enum TestDoubles {
    static func makeUserDefaults(testName: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "VoiceCoreTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        url = directoryURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
