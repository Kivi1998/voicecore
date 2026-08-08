// VoicecoreLogger.swift
// Provides typed category loggers backed by swift-log.

import Logging

struct VoicecoreLogger: Sendable {
    private let category: VoicecoreLogCategory
    private let logger: Logger

    nonisolated init(category: VoicecoreLogCategory) {
        self.category = category
        LoggingBootstrap.bootstrapIfNeeded()
        let logger = Logger(label: "Voicecore.\(category.rawValue)")
        self.logger = logger
    }

    nonisolated func trace(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .trace, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func debug(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .debug, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func info(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .info, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func notice(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic,
        verbose: Bool = false
    ) {
        log(level: .notice, message: message, metadata: metadata, privacy: privacy, verbose: verbose)
    }

    nonisolated func warning(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic
    ) {
        log(level: .warning, message: message, metadata: metadata, privacy: privacy)
    }

    nonisolated func error(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic
    ) {
        log(level: .error, message: message, metadata: metadata, privacy: privacy)
    }

    nonisolated func critical(
        _ message: @autoclosure () -> String,
        metadata: Logger.Metadata? = nil,
        privacy: VoicecoreLogPrivacy = .automatic
    ) {
        log(level: .critical, message: message, metadata: metadata, privacy: privacy)
    }

    private nonisolated func log(
        level: Logger.Level,
        message: () -> String,
        metadata: Logger.Metadata?,
        privacy: VoicecoreLogPrivacy,
        verbose: Bool = false
    ) {
        guard !verbose || VoicecoreLog.verboseEnabled else { return }
        let redactedMessage = VoicecoreLogRedactor.redact(message(), privacy: privacy)
        let metadata = VoicecoreLogRedactor.redactedMetadata(metadata) ?? [:]
        logger.log(level: level, "\(redactedMessage)", metadata: metadata)
    }
}
