// VoiceCoreLogExportStore.swift
// Provides display and export payloads for local diagnostic logs.

import Foundation

enum VoiceCoreLogExportStore {
    nonisolated static func latestLogUpdateDate() -> Date? {
        VoiceCoreLogFileStore.shared.latestLogUpdateDate()
    }

    nonisolated static func latestLogDisplayText(limit: Int = 1_000, metadataProvider: () -> String) -> String {
        let selectedLines = VoiceCoreLogFileStore.shared.latestLines(limit: limit)
        let unavailableText = MainActorSync.run {
            AppLocalization.localizedString("No logs available")
        }
        let appMetaTitle = MainActorSync.run {
            AppLocalization.localizedString("App Meta")
        }
        let logText = selectedLines.isEmpty
            ? "[VoiceCore] <\(unavailableText)>"
            : selectedLines.joined(separator: "\n")

        return [
            logText,
            "========== \(appMetaTitle) ==========",
            VoiceCoreLogRedactor.redact(metadataProvider())
        ].joined(separator: "\n\n")
    }
}
