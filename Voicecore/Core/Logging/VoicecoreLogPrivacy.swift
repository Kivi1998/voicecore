// VoiceCoreLogPrivacy.swift
// Defines privacy handling for log messages before they leave the app process.

enum VoiceCoreLogPrivacy: Sendable {
    case automatic
    case visible
    case sensitive
    case preview(limit: Int)
}
