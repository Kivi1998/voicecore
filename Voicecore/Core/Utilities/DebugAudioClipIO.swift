// DebugAudioClipIO.swift
// Shared helpers for reading debug/test audio clips used by remote ASR debug tooling.

import Foundation
import AVFoundation

struct DebugAudioClip: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let durationSeconds: Double
    let sampleRate: Double
    let createdAt: Date

    var summaryText: String {
        let duration = String(format: "%.1f", durationSeconds)
        let rate = Int(sampleRate.rounded())
        return "\(duration)s · \(rate) Hz"
    }
}

nonisolated enum DebugAudioClipIO {
    static func temporaryClipURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceCore-Debug-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    static func clip(for fileURL: URL) throws -> DebugAudioClip {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate > 0
            ? Double(file.length) / sampleRate
            : 0
        return DebugAudioClip(
            id: UUID(),
            fileURL: fileURL,
            durationSeconds: duration,
            sampleRate: sampleRate,
            createdAt: Date()
        )
    }

    static func loadMonoSamples(from fileURL: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "VoiceCore.ModelDebug",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Unable to allocate audio buffer.")]
            )
        }
        try file.read(into: buffer)

        if let mono = AudioLevelMeter.monoSamples(from: buffer) {
            return (mono, format.sampleRate)
        }

        throw NSError(
            domain: "VoiceCore.ModelDebug",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Unable to decode audio samples.")]
        )
    }
}
