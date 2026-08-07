import Foundation
@testable import OpenTypelessApplication
import OpenTypelessData
import OpenTypelessDomain

// MARK: - 测试装置

final class Fixture {
    let records: DictationRecordStore
    let audioFiles: FileAudioFileStore
    let recordingsRoot: URL
    let capture: FakeAudioCapture
    let factory: FakeProviderFactory
    let options = FakeOptionsProvider()
    let clipboard = FakeClipboardService()
    let injector = FakeTextInjector()
    let orchestrator: DictationOrchestrator

    var speech: FakeSpeechProvider {
        factory.speech
    }

    var rewrite: FakeRewriteProvider {
        factory.rewrite
    }

    init(root: URL) throws {
        let manager = try DatabaseManager(path: root.appendingPathComponent("test.sqlite").path)
        records = DictationRecordStore(pool: manager.pool)
        recordingsRoot = root.appendingPathComponent("recordings", isDirectory: true)
        audioFiles = FileAudioFileStore(recordingsRoot: recordingsRoot)
        capture = FakeAudioCapture(audioFiles: audioFiles)
        factory = FakeProviderFactory()
        let rootURL = recordingsRoot
        orchestrator = DictationOrchestrator(
            records: records,
            audioFiles: audioFiles,
            audioCapture: capture,
            providerFactory: factory,
            optionsProvider: options,
            clipboard: clipboard,
            injector: injector,
            audioURLResolver: { relativePath in
                rootURL.appendingPathComponent(relativePath, isDirectory: false)
            }
        )
    }
}

// MARK: - 替身

actor FakeAudioCapture: AudioCapture {
    let audioFiles: FileAudioFileStore
    private var writer: (any AudioFileWriting)?
    private var currentPath: String?
    private(set) var cancelCalled = false

    init(audioFiles: FileAudioFileStore) {
        self.audioFiles = audioFiles
    }

    nonisolated var events: AsyncStream<AudioCaptureEvent> {
        AsyncStream { $0.finish() }
    }

    nonisolated func listInputDevices() async throws -> [AudioInputDevice] {
        []
    }

    func start(deviceID _: String?, writingTo relativePath: String) async throws {
        let writer = try audioFiles.openForWriting(relativePath: relativePath)
        // 模拟边录边写：写入若干字节使 finalize 校验通过。
        try writer.append(Data(repeating: 0x61, count: 64))
        self.writer = writer
        currentPath = relativePath
    }

    func stop() async throws -> AudioCaptureResult {
        guard let writer, let path = currentPath else {
            throw DictationError(category: .audioInvalid, userMessage: "没有进行中的录音")
        }
        try writer.close()
        self.writer = nil
        return AudioCaptureResult(
            relativePath: path,
            mimeType: "audio/mp4",
            durationMs: 1200,
            sizeBytes: 64
        )
    }

    func cancel() async {
        try? writer?.close()
        writer = nil
        cancelCalled = true
    }
}

final class FakeSpeechProvider: SpeechProvider, @unchecked Sendable {
    var result: Result<SpeechResult, DictationError> = .success(SpeechResult(text: ""))
    private(set) var callCount = 0

    var capabilities: SpeechCapabilities {
        SpeechCapabilities(supportsFileUpload: true, supportsLanguageHint: true, supportsVocabularyPrompt: true)
    }

    func validate() async throws -> ValidationResult {
        .success(latencyMs: 1)
    }

    func transcribe(_: SpeechRequest) async throws -> SpeechResult {
        callCount += 1
        return try result.get()
    }
}

final class FakeRewriteProvider: RewriteProvider, @unchecked Sendable {
    var result: Result<RewriteResult, DictationError> = .success(RewriteResult(finalText: ""))
    private(set) var callCount = 0

    var capabilities: RewriteCapabilities {
        RewriteCapabilities()
    }

    func validate() async throws -> ValidationResult {
        .success(latencyMs: 1)
    }

    func rewrite(_: RewriteRequest) async throws -> RewriteResult {
        callCount += 1
        return try result.get()
    }
}

final class FakeProviderFactory: ProviderFactory, @unchecked Sendable {
    let speech = FakeSpeechProvider()
    let rewrite = FakeRewriteProvider()
    var speechPair: (any SpeechProvider, ProviderProfileSnapshot)?
    var rewritePair: (any RewriteProvider, ProviderProfileSnapshot)?

    init() {
        speechPair = (speech, ProviderProfileSnapshot(
            profileID: nil,
            name: "测试语音",
            protocolKind: .openAIAudioTranscription,
            baseURL: "https://example.test",
            modelName: "test-speech"
        ))
        rewritePair = (rewrite, ProviderProfileSnapshot(
            profileID: nil,
            name: "测试改写",
            protocolKind: .openAIChat,
            baseURL: "https://example.test",
            modelName: "test-rewrite"
        ))
    }

    func makeSpeechProvider() async throws -> (any SpeechProvider, ProviderProfileSnapshot)? {
        speechPair
    }

    func makeRewriteProvider() async throws -> (any RewriteProvider, ProviderProfileSnapshot)? {
        rewritePair
    }

    func vocabularyTerms() async throws -> [String] {
        []
    }
}

final class FakeOptionsProvider: PipelineOptionsProvider, @unchecked Sendable {
    var options = PipelineOptions()
    func currentOptions() async throws -> PipelineOptions {
        options
    }
}

final class FakeClipboardService: ClipboardService, @unchecked Sendable {
    private(set) var saveCount = 0
    private(set) var restoreCount = 0
    private(set) var writtenTexts: [String] = []

    func save() async -> ClipboardSnapshot {
        saveCount += 1
        return .empty
    }

    func writeText(_ text: String) async {
        writtenTexts.append(text)
    }

    func readText() async -> String? {
        nil
    }

    func restore(_: ClipboardSnapshot) async throws {
        restoreCount += 1
    }
}

final class FakeTextInjector: TextInjector, @unchecked Sendable {
    var error: DictationError?
    private(set) var inserted: [String] = []

    func insert(_ text: String) async throws {
        if let error {
            throw error
        }
        inserted.append(text)
    }
}
