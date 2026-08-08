// VoicecoreNoteRemindersExportStore.swift
// Provides Voicecore Note Reminders Export Store for core app behavior.

import Foundation

struct VoicecoreNoteRemindersExportRecord: Codable, Hashable, Sendable {
    let noteID: UUID
    let reminderCalendarItemIdentifier: String
    let selectedListIdentifierAtCreation: String
}

final class VoicecoreNoteRemindersExportStore {
    private let fileManager: FileManager
    private let persistenceCoordinator = AsyncJSONPersistenceCoordinator(
        label: "com.kivi.voicecore.note-reminders-export.persistence"
    )
    private let fileURLOverride: URL?

    private(set) var recordsByNoteID: [UUID: VoicecoreNoteRemindersExportRecord] = [:]

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURLOverride = fileURL
        reload()
    }

    func reload() {
        do {
            let fileURL = try exportStoreFileURL()
            guard fileManager.fileExists(atPath: fileURL.path) else {
                recordsByNoteID = [:]
                return
            }

            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([VoicecoreNoteRemindersExportRecord].self, from: data)
            recordsByNoteID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.noteID, $0) })
        } catch {
            recordsByNoteID = [:]
        }
    }

    func upsert(_ record: VoicecoreNoteRemindersExportRecord) {
        recordsByNoteID[record.noteID] = record
        persist()
    }

    func remove(noteID: UUID) -> VoicecoreNoteRemindersExportRecord? {
        let removed = recordsByNoteID.removeValue(forKey: noteID)
        persist()
        return removed
    }

    func replaceAll(_ records: [VoicecoreNoteRemindersExportRecord]) {
        recordsByNoteID = Dictionary(uniqueKeysWithValues: records.map { ($0.noteID, $0) })
        persist()
    }

    private func persist() {
        do {
            let fileURL = try exportStoreFileURL()
            let orderedRecords = recordsByNoteID.values.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
            persistenceCoordinator.scheduleWrite(orderedRecords, to: fileURL)
        } catch {
            return
        }
    }

    private func exportStoreFileURL() throws -> URL {
        if let fileURLOverride {
            return fileURLOverride
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voicecore", isDirectory: true)
            .appendingPathComponent("voicecore-note-reminders-exports.json")
    }
}
