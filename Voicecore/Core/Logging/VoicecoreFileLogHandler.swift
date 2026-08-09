// VoiceCoreFileLogHandler.swift
// Bridges swift-log records into VoiceCore rolling diagnostic files.

import Foundation
import Logging

struct VoiceCoreFileLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?
    var logLevel: Logger.Level = .info

    private let label: String
    private let category: VoiceCoreLogCategory
    private let fileStore: VoiceCoreLogFileStore

    init(label: String, category: VoiceCoreLogCategory, fileStore: VoiceCoreLogFileStore = .shared) {
        self.label = label
        self.category = category
        self.fileStore = fileStore
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    func log(event: LogEvent) {
        guard !VoiceCoreRuntimeEnvironment.isRunningUnitTests else { return }
        let mergedMetadata = mergedMetadata(event.metadata)
        let redactedMetadata = VoiceCoreLogRedactor.redactedMetadata(mergedMetadata)
        let redactedMessage = VoiceCoreLogRedactor.redact(event.message.description)
        let formattedLine = VoiceCoreLogFormatter.line(
            level: event.level,
            category: category,
            message: redactedMessage,
            metadata: redactedMetadata,
            source: event.source.isEmpty ? label : event.source,
            file: event.file,
            function: event.function,
            line: event.line
        )
        fileStore.append(formattedLine)
    }

    private func mergedMetadata(_ explicitMetadata: Logger.Metadata?) -> Logger.Metadata? {
        var merged = metadataProvider?.get() ?? [:]
        for (key, value) in metadata where merged[key] == nil {
            merged[key] = value
        }
        if let explicitMetadata {
            for (key, value) in explicitMetadata {
                merged[key] = value
            }
        }
        return merged.isEmpty ? nil : merged
    }
}
