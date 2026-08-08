// VoicecoreLogExportStore.swift
// Provides display and export payloads for local diagnostic logs.

import Foundation

enum VoicecoreLogExportStore {
    nonisolated static func latestLogUpdateDate() -> Date? {
        VoicecoreLogFileStore.shared.latestLogUpdateDate()
    }

    nonisolated static func latestLogDisplayText(limit: Int = 1_000, metadataProvider: () -> String) -> String {
        let selectedLines = VoicecoreLogFileStore.shared.latestLines(limit: limit)
        let unavailableText = MainActorSync.run {
            AppLocalization.localizedString("No logs available")
        }
        let appMetaTitle = MainActorSync.run {
            AppLocalization.localizedString("App Meta")
        }
        let logText = selectedLines.isEmpty
            ? "[Voicecore] <\(unavailableText)>"
            : selectedLines.joined(separator: "\n")

        return [
            logText,
            "========== \(appMetaTitle) ==========",
            VoicecoreLogRedactor.redact(metadataProvider())
        ].joined(separator: "\n\n")
    }
}
