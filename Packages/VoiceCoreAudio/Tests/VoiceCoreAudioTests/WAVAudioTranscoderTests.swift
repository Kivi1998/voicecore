import AVFAudio
import Foundation
@testable import VoiceCoreAudio
import XCTest

final class WAVAudioTranscoderTests: XCTestCase {
    func testPassesWAVDataThroughUnchanged() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let bytes = Data("RIFF-test-WAVE".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try WAVAudioTranscoder().wavData(from: url), bytes)
    }

    func testConvertsM4AToPCM16WAV() throws {
        let directory = FileManager.default.temporaryDirectory
        let source = directory.appendingPathComponent("\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: source) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        try writeTestAudio(to: source, settings: settings)

        let data = try WAVAudioTranscoder().wavData(from: source)
        XCTAssertGreaterThan(data.count, 44)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
    }

    private func writeTestAudio(to url: URL, settings: [String: Any]) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410) else {
            return XCTFail("无法建立测试音频")
        }
        buffer.frameLength = 4410
        for index in 0 ..< Int(buffer.frameLength) {
            buffer.floatChannelData?[0][index] = sin(Float(index) * 2 * .pi * 440 / 44100) * 0.2
        }
        try file.write(from: buffer)
    }
}
