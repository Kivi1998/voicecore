import AudioToolbox
import Foundation
import VoiceCoreDomain

/// 将 VoiceCore 录制的 AAC/M4A 解码为豆包支持的 16 kHz 单声道 PCM16 WAV。
public struct WAVAudioTranscoder: Sendable {
    private static let sampleRate: UInt32 = 16000

    public init() {}

    public func wavData(from sourceURL: URL) throws -> Data {
        if sourceURL.pathExtension.lowercased() == "wav" {
            return try read(sourceURL)
        }

        let pcm = try decodePCM(from: sourceURL)
        guard !pcm.isEmpty else {
            throw audioError("录音文件没有可识别的音频")
        }
        return Self.makeWAV(pcm: pcm)
    }

    private func decodePCM(from sourceURL: URL) throws -> Data {
        var file: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(sourceURL as CFURL, &file) == noErr, let file else {
            throw audioError("无法打开录音文件")
        }
        defer { ExtAudioFileDispose(file) }

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: Double(Self.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        let formatStatus = withUnsafePointer(to: &clientFormat) { pointer in
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                pointer
            )
        }
        guard formatStatus == noErr else {
            throw audioError("无法建立录音转码器")
        }

        var pcm = Data()
        let chunkFrames: UInt32 = 4096
        while true {
            var frames = chunkFrames
            var chunk = Data(count: Int(chunkFrames) * 2)
            let status = chunk.withUnsafeMutableBytes { bytes -> OSStatus in
                var bufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(bytes.count),
                        mData: bytes.baseAddress
                    )
                )
                return ExtAudioFileRead(file, &frames, &bufferList)
            }
            guard status == noErr else {
                throw audioError("录音解码失败")
            }
            guard frames > 0 else { break }
            pcm.append(chunk.prefix(Int(frames) * 2))
        }
        return pcm
    }

    private static func makeWAV(pcm: Data) -> Data {
        var result = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &result)
        result.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &result)
        append(UInt16(1), to: &result)
        append(UInt16(1), to: &result)
        append(sampleRate, to: &result)
        append(sampleRate * 2, to: &result)
        append(UInt16(2), to: &result)
        append(UInt16(16), to: &result)
        result.append(Data("data".utf8))
        append(UInt32(pcm.count), to: &result)
        result.append(pcm)
        return result
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw audioError("无法读取录音文件")
        }
    }

    private func audioError(_ message: String) -> DictationError {
        DictationError(category: .audioInvalid, userMessage: message, isRetryable: false)
    }
}
