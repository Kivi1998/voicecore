// InteractionSoundPlayer.swift
// Provides Interaction Sound Player for core app behavior.

import AVFoundation
import Foundation

@MainActor
final class InteractionSoundPlayer {
    private let volume: Float = 1
    private let startSoundData = InteractionSoundPlayer.bundledSoundData(named: "record-start")
    private let endSoundData = InteractionSoundPlayer.bundledSoundData(named: "record-end")
    private var activePlayer: AVAudioPlayer?

    @discardableResult
    func playStart() -> TimeInterval {
        play(data: startSoundData, cue: "record-start")
    }

    @discardableResult
    func playEnd() -> TimeInterval {
        play(data: endSoundData, cue: "record-end")
    }

    @discardableResult
    func playPreview() -> TimeInterval {
        playStart()
    }

    func reset() {
        activePlayer?.stop()
        activePlayer = nil
    }

    private func play(data: Data?, cue: String) -> TimeInterval {
        guard let data else {
            VoiceCoreLog.audioWarning("Bundled interaction sound is missing. cue=\(cue)")
            return 0
        }

        do {
            // Keep the WAV bytes resident so the physical fn event never waits on file I/O.
            // A fresh player also avoids stale AudioUnits after a long idle/sleep period.
            let player = try AVAudioPlayer(data: data)
            player.volume = volume
            player.prepareToPlay()
            guard player.play() else { return 0 }
            activePlayer = player
            return player.duration
        } catch {
            VoiceCoreLog.audioWarning("Interaction sound failed to initialize. cue=\(cue), error=\(error.localizedDescription)")
            activePlayer = nil
            return 0
        }
    }

    private static func bundledSoundData(named name: String) -> Data? {
        let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(
                forResource: name,
                withExtension: "wav",
                subdirectory: "Resources/Sounds"
            )
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
