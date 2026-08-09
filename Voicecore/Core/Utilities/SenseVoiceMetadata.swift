// SenseVoiceMetadata.swift
// Provides Sense Voice Metadata for shared utilities.

import Foundation

struct SenseVoiceSegmentMetadata: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
    let language: String?
    let emotion: String?
    let event: String?

    nonisolated init(
        id: UUID = UUID(),
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        text: String,
        language: String?,
        emotion: String?,
        event: String?
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.language = language
        self.emotion = emotion
        self.event = event
    }
}

struct SenseVoiceTranscriptMetadata: Codable, Hashable, Sendable {
    let language: String?
    let emotion: String?
    let event: String?
    let usedVADSegmentation: Bool
    let segments: [SenseVoiceSegmentMetadata]

    func formattedDebugSummary(appendingTranscript transcript: String) -> String {
        var lines: [String] = []
        lines.append("Transcript:")
        lines.append(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        lines.append("SenseVoice Metadata:")
        lines.append("Language: \(language ?? "unknown")")
        lines.append("Emotion: \(emotion ?? "unknown")")
        lines.append("Event: \(event ?? "unknown")")
        lines.append("VAD Segmentation: \(usedVADSegmentation ? "on" : "off")")
        if !segments.isEmpty {
            lines.append("")
            lines.append("Segments:")
            for segment in segments {
                let start = TranscriptFormatter.timestampString(for: segment.startSeconds)
                let end = TranscriptFormatter.timestampString(for: segment.endSeconds)
                let labels = [segment.language, segment.emotion, segment.event]
                    .compactMap { value -> String? in
                        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .joined(separator: " / ")
                if labels.isEmpty {
                    lines.append("[\(start)-\(end)] \(segment.text)")
                } else {
                    lines.append("[\(start)-\(end)] \(labels): \(segment.text)")
                }
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
