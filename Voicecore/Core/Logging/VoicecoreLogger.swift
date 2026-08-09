// VoiceCoreLogger.swift
// Provides typed category loggers backed by swift-log.

import Logging

struct VoiceCoreLogger: Sendable {
    private let category: VoiceCoreLogCategory
    private let logger: Logger

    nonisolated init(category: VoiceCoreLogCategory) {
        self.category = category
        LoggingBootstrap.bootstrapIfNeeded()
        let logger = Logger(label: "VoiceCore.\(category.rawValue)")
        self.logger = logger
    }

    nonisolated func trace(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .trace, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func debug(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .debug, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func info(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .info, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func notice(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .notice, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func warning(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic
    ) {
        log(level: .warning, message: message, metadata: metadata, privacy: privacy)
    }

    nonisolated func error(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic
    ) {
        log(level: .error, message: message, metadata: metadata, privacy: privacy)
    }

    nonisolated func critical(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoiceCoreLogPrivacy = .automatic
    ) {
        log(level: .critical, message: message, metadata: metadata, privacy: privacy)
    }

    private nonisolated func log(
        level: Logger.Level,
        message: () -> String,
        metadata: Logger.Metadata?,
        privacy: VoiceCoreLogPrivacy,
        verbose: Bool = false
    ) {
        guard !verbose || VoiceCoreLog.verboseEnabled else { return }
        let redactedMessage = VoiceCoreLogRedactor.redact(message(), privacy: privacy)
        let metadata = VoiceCoreLogRedactor.redactedMetadata(metadata) ?? [:]
        logger.log(level: level, "\(redactedMessage)", metadata: metadata)
    }
}
