import Foundation
import XCTest
@testable import OpenTypelessApplication
import OpenTypelessDomain
import OpenTypelessData

/// 口述编排器测试（CORE-004）。
///
/// 使用真实 GRDB 临时数据库与真实 FileAudioFileStore 验证端到端状态推进、
/// 尝试记录写回与失败保留语义；采集、提供商、剪贴板与注入使用内存替身。
final class DictationOrchestratorTests: XCTestCase {
    private var tempDir: URL!
    private var fixture: Fixture!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchestrator-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fixture = try Fixture(root: tempDir)
    }

    override func tearDownWithError() throws {
        fixture = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 全流程成功

    func testFullPipelineWithRewriteCompletes() async throws {
        fixture.speech.result = .success(SpeechResult(text: "你好 world", detectedLanguage: "zh"))
        fixture.rewrite.result = .success(RewriteResult(finalText: "你好，world。"))
        fixture.options.options = PipelineOptions(rewriteEnabled: true, autoInsert: true, restoreClipboard: true)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        let record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.rawTranscript, "你好 world")
        XCTAssertEqual(record.finalText, "你好，world。")
        XCTAssertEqual(record.countUnits, UnitCounter.count("你好，world。"))
        XCTAssertEqual(record.durationMs, 1_200)
        XCTAssertNotNil(record.completedAt)
        XCTAssertEqual(record.detectedLanguage, "zh")

        // 注入与剪贴板恢复。
        XCTAssertEqual(fixture.injector.inserted, ["你好，world。"])
        XCTAssertEqual(fixture.clipboard.saveCount, 1)
        XCTAssertEqual(fixture.clipboard.restoreCount, 1)

        // 尝试记录完整写回。
        let attempts = try await fixture.records.attempts(recordID: recordID)
        XCTAssertEqual(attempts.count, 2)
        let transcription = try XCTUnwrap(attempts.first { $0.stage == .transcription })
        XCTAssertEqual(transcription.success, true)
        XCTAssertNotNil(transcription.finishedAt)
        XCTAssertNotNil(transcription.latencyMs)
        let rewrite = try XCTUnwrap(attempts.first { $0.stage == .rewrite })
        XCTAssertEqual(rewrite.success, true)
    }

    func testPipelineWithoutRewriteUsesRawTranscript() async throws {
        fixture.speech.result = .success(SpeechResult(text: "原始文字"))
        fixture.options.options = PipelineOptions(rewriteEnabled: false, autoInsert: true)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        let record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.finalText, "原始文字")
        XCTAssertEqual(fixture.rewrite.callCount, 0)
        XCTAssertEqual(fixture.injector.inserted, ["原始文字"])
    }

    func testPipelineWithoutAutoInsertCompletesWithoutInjection() async throws {
        fixture.speech.result = .success(SpeechResult(text: "只保存"))
        fixture.options.options = PipelineOptions(rewriteEnabled: false, autoInsert: false)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        let record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.finalText, "只保存")
        XCTAssertTrue(fixture.injector.inserted.isEmpty)
    }

    // MARK: - 失败保留与重试

    func testTranscriptionFailureKeepsAudioAndAllowsRetry() async throws {
        fixture.speech.result = .failure(DictationError(category: .networkUnavailable, userMessage: "网络不可用"))
        fixture.options.options = PipelineOptions(rewriteEnabled: false)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        var record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .transcriptionFailed)
        XCTAssertNil(record.rawTranscript)
        // 音频文件保留。
        let audioPath = try XCTUnwrap(record.audioRelativePath)
        XCTAssertTrue(try fixture.audioFiles.info(relativePath: audioPath).exists)
        // 失败尝试已写回。
        var attempts = try await fixture.records.attempts(recordID: recordID)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].success, false)
        XCTAssertEqual(attempts[0].errorCategory, .networkUnavailable)

        // 网络恢复后使用原录音重试成功。
        fixture.speech.result = .success(SpeechResult(text: "重试成功"))
        try await fixture.orchestrator.retryTranscription(recordID: recordID)
        record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.finalText, "重试成功")
        XCTAssertEqual(record.retryCount, 1)
        attempts = try await fixture.records.attempts(recordID: recordID)
        XCTAssertEqual(attempts.filter { $0.stage == .transcription }.count, 2)
    }

    func testRewriteFailureKeepsRawTranscriptAndRetrySkipsSpeech() async throws {
        fixture.speech.result = .success(SpeechResult(text: "原始转录"))
        fixture.rewrite.result = .failure(DictationError(category: .rateLimited, userMessage: "限流"))
        fixture.options.options = PipelineOptions(rewriteEnabled: true, autoInsert: false)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        var record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .rewriteFailed)
        XCTAssertEqual(record.rawTranscript, "原始转录")
        XCTAssertNil(record.finalText)
        XCTAssertEqual(fixture.speech.callCount, 1)

        // 仅重新改写：不再调用语音识别。
        fixture.rewrite.result = .success(RewriteResult(finalText: "改写后的文字"))
        try await fixture.orchestrator.retryRewrite(recordID: recordID)
        record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.finalText, "改写后的文字")
        XCTAssertEqual(fixture.speech.callCount, 1)
        XCTAssertEqual(fixture.rewrite.callCount, 2)
    }

    func testInjectionFailureKeepsFinalText() async throws {
        fixture.speech.result = .success(SpeechResult(text: "最终文字"))
        fixture.injector.error = DictationError(
            category: .injectionTargetUnavailable,
            userMessage: "目标不可写入"
        )
        fixture.options.options = PipelineOptions(rewriteEnabled: false, autoInsert: true)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        let record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .injectionFailed)
        XCTAssertEqual(record.finalText, "最终文字")
        XCTAssertNil(record.completedAt)
    }

    func testRetryInjectionInsertsFinalTextAndCompletes() async throws {
        fixture.speech.result = .success(SpeechResult(text: "最终文字"))
        fixture.injector.error = DictationError(
            category: .injectionTargetUnavailable,
            userMessage: "目标不可写入"
        )
        fixture.options.options = PipelineOptions(rewriteEnabled: false, autoInsert: true)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        _ = try await waitForSettled(recordID)

        // 注入目标恢复后重试：写入最终文字并完成。
        fixture.injector.error = nil
        try await fixture.orchestrator.retryInjection(recordID: recordID)
        let record = try await waitForSettled(recordID)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(fixture.injector.inserted, ["最终文字"])
        XCTAssertNotNil(record.completedAt)
    }

    func testRetryInjectionRejectsNonInjectionFailedStatus() async throws {
        fixture.speech.result = .success(SpeechResult(text: "文字"))
        fixture.options.options = PipelineOptions(rewriteEnabled: false, autoInsert: true)

        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.stopRecording()
        let record = try await waitForSettled(recordID)
        XCTAssertEqual(record.status, .completed)

        do {
            try await fixture.orchestrator.retryInjection(recordID: recordID)
            XCTFail("非输入失败状态应拒绝重新输入")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        }
    }

    // MARK: - 会话控制

    func testDuplicateStartRecordingIsRejected() async throws {
        _ = try await fixture.orchestrator.startRecording()
        do {
            _ = try await fixture.orchestrator.startRecording()
            XCTFail("重复开始录音应被拒绝")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        }
        await fixture.orchestrator.cancelRecording()
    }

    func testCancelRecordingMarksCancelled() async throws {
        let recordID = try await fixture.orchestrator.startRecording()
        await fixture.orchestrator.cancelRecording()

        let record = try await fixture.records.get(id: recordID)
        XCTAssertEqual(record?.status, .cancelled)
        XCTAssertTrue(fixture.capture.cancelCalled)
    }

    func testStartRecordingWithoutSpeechConfigurationThrows() async throws {
        fixture.factory.speechPair = nil
        do {
            _ = try await fixture.orchestrator.startRecording()
            XCTFail("缺少语音配置应拒绝开始")
        } catch let error as DictationError {
            XCTAssertEqual(error.category, .configurationInvalid)
        }
    }

    // MARK: - 工具

    private static let settledStatuses: Set<DictationStatus> = [
        .completed, .cancelled, .transcriptionFailed, .rewriteFailed, .injectionFailed, .recordingFailed,
    ]

    /// 轮询直到记录进入停滞态（流水线在后台任务中执行）。
    private func waitForSettled(_ recordID: UUID, timeout: TimeInterval = 10) async throws -> DictationRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let record = try await fixture.records.get(id: recordID),
               Self.settledStatuses.contains(record.status) {
                // 停滞态之后后台任务可能仍在收尾（activeRecordID 复位），稍等一拍。
                try await Task.sleep(nanoseconds: 50_000_000)
                return record
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let status = try await fixture.records.get(id: recordID)?.status
        XCTFail("等待记录停滞超时，当前状态：\(String(describing: status))")
        throw CancellationError()
    }
}

// MARK: - 测试装置

private final class Fixture {
    let records: DictationRecordStore
    let audioFiles: FileAudioFileStore
    let recordingsRoot: URL
    let capture: FakeAudioCapture
    let factory: FakeProviderFactory
    let options = FakeOptionsProvider()
    let clipboard = FakeClipboardService()
    let injector = FakeTextInjector()
    let orchestrator: DictationOrchestrator

    var speech: FakeSpeechProvider { factory.speech }
    var rewrite: FakeRewriteProvider { factory.rewrite }

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

private final class FakeAudioCapture: AudioCapture, @unchecked Sendable {
    let audioFiles: FileAudioFileStore
    private let lock = NSLock()
    private var writer: (any AudioFileWriting)?
    private var currentPath: String?
    private(set) var cancelCalled = false

    init(audioFiles: FileAudioFileStore) {
        self.audioFiles = audioFiles
    }

    var events: AsyncStream<AudioCaptureEvent> { AsyncStream { $0.finish() } }

    func listInputDevices() async throws -> [AudioInputDevice] { [] }

    func start(deviceID: String?, writingTo relativePath: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        let writer = try audioFiles.openForWriting(relativePath: relativePath)
        // 模拟边录边写：写入若干字节使 finalize 校验通过。
        try writer.append(Data(repeating: 0x61, count: 64))
        self.writer = writer
        currentPath = relativePath
    }

    func stop() async throws -> AudioCaptureResult {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, let path = currentPath else {
            throw DictationError(category: .audioInvalid, userMessage: "没有进行中的录音")
        }
        try writer.close()
        self.writer = nil
        return AudioCaptureResult(
            relativePath: path,
            mimeType: "audio/mp4",
            durationMs: 1_200,
            sizeBytes: 64
        )
    }

    func cancel() async {
        lock.lock()
        defer { lock.unlock() }
        try? writer?.close()
        writer = nil
        cancelCalled = true
    }
}

private final class FakeSpeechProvider: SpeechProvider, @unchecked Sendable {
    var result: Result<SpeechResult, DictationError> = .success(SpeechResult(text: ""))
    private(set) var callCount = 0

    var capabilities: SpeechCapabilities {
        SpeechCapabilities(supportsFileUpload: true, supportsLanguageHint: true, supportsVocabularyPrompt: true)
    }

    func validate() async throws -> ValidationResult { .success(latencyMs: 1) }

    func transcribe(_ request: SpeechRequest) async throws -> SpeechResult {
        callCount += 1
        return try result.get()
    }
}

private final class FakeRewriteProvider: RewriteProvider, @unchecked Sendable {
    var result: Result<RewriteResult, DictationError> = .success(RewriteResult(finalText: ""))
    private(set) var callCount = 0

    var capabilities: RewriteCapabilities { RewriteCapabilities() }

    func validate() async throws -> ValidationResult { .success(latencyMs: 1) }

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        callCount += 1
        return try result.get()
    }
}

private final class FakeProviderFactory: ProviderFactory, @unchecked Sendable {
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

    func vocabularyTerms() async throws -> [String] { [] }
}

private final class FakeOptionsProvider: PipelineOptionsProvider, @unchecked Sendable {
    var options = PipelineOptions()
    func currentOptions() async throws -> PipelineOptions { options }
}

private final class FakeClipboardService: ClipboardService, @unchecked Sendable {
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

    func readText() async -> String? { nil }

    func restore(_ snapshot: ClipboardSnapshot) async throws {
        restoreCount += 1
    }
}

private final class FakeTextInjector: TextInjector, @unchecked Sendable {
    var error: DictationError?
    private(set) var inserted: [String] = []

    func insert(_ text: String) async throws {
        if let error { throw error }
        inserted.append(text)
    }
}
