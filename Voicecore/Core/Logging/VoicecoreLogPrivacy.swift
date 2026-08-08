// VoicecoreLogPrivacy.swift
// Defines privacy handling for log messages before they leave the app process.

enum VoicecoreLogPrivacy: Sendable {
    case automatic
    case visible
    case sensitive
    case preview(limit: Int)
}
