// LoggingBootstrap.swift
// Installs the VoiceCore swift-log backend once during app startup.

import Foundation
import Logging

enum LoggingBootstrap {
    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var didBootstrap = false

    nonisolated static func bootstrapIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didBootstrap else { return }
        didBootstrap = true
        LoggingSystem.bootstrap { label in
            let category = Self.category(from: label)
            return VoiceCoreMultiplexLogHandler(label: label, category: category)
        }
    }

    nonisolated static func bootstrap() {
        bootstrapIfNeeded()
    }

    private nonisolated static func category(from label: String) -> VoiceCoreLogCategory {
        let suffix = label.split(separator: ".").last.map(String.init) ?? ""
        return VoiceCoreLogCategory(rawValue: suffix) ?? .app
    }
}
