import Foundation
@testable import VoiceCoreApplication
import VoiceCoreData
import VoiceCoreDomain
import XCTest

/// 口述编排器测试（CORE-004）。
///
/// 使用真实 GRDB 临时数据库与真实 FileAudioFileStore 验证端到端状态推进、
/// 尝试记录写回与失败保留语义；采集、提供商、剪贴板与注入使用内存替身。
final class DictationOrchestratorTests: XCTestCase {
    // XCTest 夹具属性的隐式解包可选值是 XCTest 官方惯例（setUpWithError 赋值）。
    // swiftlint:disable implicitly_unwrapped_optional
    private var tempDir: URL!
    private var fixture: Fixture!
    // swiftlint:enable implicitly_unwrapped_optional

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
        XCTAssertEqual(record.durationMs, 1200)
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
        record = try await waitForSettled(recordID, afterUpdatedAt: record.updatedAt)

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
        record = try await waitForSettled(recordID, afterUpdatedAt: record.updatedAt)

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
        let failed = try await waitForSettled(recordID)

        // 注入目标恢复后重试：写入最终文字并完成。
        fixture.injector.error = nil
        try await fixture.orchestrator.retryInjection(recordID: recordID)
        let record = try await waitForSettled(recordID, afterUpdatedAt: failed.updatedAt)

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
        let cancelCalled = await fixture.capture.cancelCalled
        XCTAssertTrue(cancelCalled)
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
        .completed, .cancelled, .transcriptionFailed, .rewriteFailed, .injectionFailed, .recordingFailed
    ]

    /// 轮询直到记录进入停滞态（流水线在后台任务中执行）。
    ///
    /// 重试场景的旧状态本身已是停滞态，必须传入 `afterUpdatedAt`（重试前的
    /// `updatedAt`）：先等记录出现新写入（`updatedAt` 前进），再等其停滞，
    /// 否则会在后台任务启动前读到陈旧记录而误判。
    private func waitForSettled(
        _ recordID: UUID,
        afterUpdatedAt baseline: Date? = nil,
        timeout: TimeInterval = 10
    ) async throws -> DictationRecord {
        let deadline = Date().addingTimeInterval(timeout)
        var observedChange = baseline == nil
        while Date() < deadline {
            if let record = try await fixture.records.get(id: recordID) {
                if !observedChange, let baseline, record.updatedAt > baseline {
                    observedChange = true
                }
                if observedChange, Self.settledStatuses.contains(record.status) {
                    // 停滞态之后后台任务可能仍在收尾（activeRecordID 复位），稍等一拍。
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return record
                }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let status = try await fixture.records.get(id: recordID)?.status
        XCTFail("等待记录停滞超时，当前状态：\(String(describing: status))")
        throw CancellationError()
    }
}
