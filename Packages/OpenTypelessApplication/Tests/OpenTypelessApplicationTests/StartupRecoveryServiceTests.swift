import Foundation
import OpenTypelessData
import OpenTypelessDomain
import XCTest
@testable import OpenTypelessApplication

/// 启动恢复服务测试（CORE-003）。
///
/// 使用真实 GRDB 临时库与真实 FileAudioFileStore 验证：
/// 强制退出后的各中间态按恢复规则转移、半成品收养、幂等且不新建记录。
final class StartupRecoveryServiceTests: XCTestCase {
    private var tempDir: URL!
    private var records: DictationRecordStore!
    private var audioFiles: FileAudioFileStore!
    private var recordingsRoot: URL!
    private var service: StartupRecoveryService!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)
        records = DictationRecordStore(pool: manager.pool)
        recordingsRoot = tempDir.appendingPathComponent("recordings", isDirectory: true)
        audioFiles = FileAudioFileStore(recordingsRoot: recordingsRoot)
        service = StartupRecoveryService(records: records, audioFiles: audioFiles)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 录音阶段恢复

    func testRecordingWithValidAudioRestoresToAudioSaved() async throws {
        let record = try await insertRecord(status: .recording, withFinalizedAudio: true)
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(report.restoredToAudioSaved, [record.id])
        await XCTAssertEqual(try status(of: record.id), .audioSaved)
    }

    func testRecordingWithOnlyPartialAdoptsPartial() async throws {
        let record = try await insertRecord(status: .recording, withPartialAudio: true)
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(report.restoredToAudioSaved, [record.id])
        XCTAssertEqual(report.adoptedPartialCount, 1)
        let updated = try await records.get(id: record.id)
        XCTAssertEqual(updated?.status, .audioSaved)
        XCTAssertEqual(updated?.audioSizeBytes, 64)
        // 半成品已收养成正式文件。
        let path = try XCTUnwrap(updated?.audioRelativePath)
        XCTAssertTrue(try audioFiles.info(relativePath: path).exists)
        XCTAssertFalse(audioFiles.hasPartial(relativePath: path))
    }

    func testRecordingWithoutAudioMarksRecordingFailed() async throws {
        let record = try await insertRecord(status: .recording)
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(report.markedRecordingFailed, [record.id])
        let updated = try await records.get(id: record.id)
        XCTAssertEqual(updated?.status, .recordingFailed)
        XCTAssertEqual(updated?.lastErrorCategory, .appInterrupted)
    }

    func testCreatedWithoutPathMarksRecordingFailed() async throws {
        let record = try await insertRecord(status: .created)
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(report.markedRecordingFailed, [record.id])
        await XCTAssertEqual(try status(of: record.id), .recordingFailed)
    }

    // MARK: - 网络与输入阶段恢复

    func testTranscribingMarksTranscriptionFailed() async throws {
        let record = try await insertRecord(status: .transcribing, withFinalizedAudio: true)
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(report.markedTranscriptionFailed, [record.id])
        let updated = try await records.get(id: record.id)
        XCTAssertEqual(updated?.status, .transcriptionFailed)
        XCTAssertEqual(updated?.lastErrorCategory, .appInterrupted)
    }

    func testTranscribedAndRewritingMarkRewriteFailed() async throws {
        let transcribed = try await insertRecord(status: .transcribed, withFinalizedAudio: true, rawTranscript: "原文")
        let rewriting = try await insertRecord(status: .rewriting, withFinalizedAudio: true, rawTranscript: "原文")
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(Set(report.markedRewriteFailed), Set([transcribed.id, rewriting.id]))
        // 原始文字保留，可仅重新改写。
        let updated = try await records.get(id: transcribed.id)
        XCTAssertEqual(updated?.status, .rewriteFailed)
        XCTAssertEqual(updated?.rawTranscript, "原文")
    }

    func testReadyAndInjectingMarkInjectionFailedWithoutAutoInsert() async throws {
        let ready = try await insertRecord(
            status: .ready,
            withFinalizedAudio: true,
            rawTranscript: "原文",
            finalText: "成品"
        )
        let injecting = try await insertRecord(
            status: .injecting,
            withFinalizedAudio: true,
            rawTranscript: "原文",
            finalText: "成品"
        )
        let report = try await service.recoverOnLaunch()

        XCTAssertEqual(Set(report.markedInjectionFailed), Set([ready.id, injecting.id]))
        // 最终文字保留；绝不自动向其他应用输入（服务不接触注入器，天然满足）。
        let updated = try await records.get(id: ready.id)
        XCTAssertEqual(updated?.status, .injectionFailed)
        XCTAssertEqual(updated?.finalText, "成品")
    }

    // MARK: - 终态与幂等

    func testTerminalStatusesAreUntouched() async throws {
        let completed = try await insertRecord(status: .completed, withFinalizedAudio: true)
        let cancelled = try await insertRecord(status: .cancelled)
        let failed = try await insertRecord(status: .recordingFailed)

        let report = try await service.recoverOnLaunch()
        XCTAssertFalse(report.hasChanges)
        await XCTAssertEqual(try status(of: completed.id), .completed)
        await XCTAssertEqual(try status(of: cancelled.id), .cancelled)
        await XCTAssertEqual(try status(of: failed.id), .recordingFailed)
    }

    func testRecoveryIsIdempotentAndCreatesNoRecords() async throws {
        _ = try await insertRecord(status: .transcribing, withFinalizedAudio: true)
        _ = try await insertRecord(status: .recording)

        let first = try await service.recoverOnLaunch()
        XCTAssertTrue(first.hasChanges)
        let countAfterFirst = try await countRecords()

        let second = try await service.recoverOnLaunch()
        XCTAssertEqual(second.scannedCount, 0)
        XCTAssertFalse(second.hasChanges)
        // 恢复只更新既有记录，不创建新记录。
        await XCTAssertEqual(try countRecords(), countAfterFirst)
    }

    // MARK: - 工具

    private func insertRecord(
        status: DictationStatus,
        withFinalizedAudio: Bool = false,
        withPartialAudio: Bool = false,
        rawTranscript: String? = nil,
        finalText: String? = nil
    ) async throws -> DictationRecord {
        let startedAt = Date()
        let recordID = UUID()
        var relativePath: String?
        if withFinalizedAudio || withPartialAudio {
            let path = try audioFiles.prepareDestination(recordID: recordID, startedAt: startedAt, fileExtension: "m4a")
            let writer = try audioFiles.openForWriting(relativePath: path)
            try writer.append(Data(repeating: 0x62, count: 64))
            try writer.close()
            if withFinalizedAudio {
                _ = try audioFiles.finalize(relativePath: path)
            }
            relativePath = path
        }
        let record = DictationRecord(
            id: recordID,
            status: status,
            startedAt: startedAt,
            audioRelativePath: relativePath,
            audioMimeType: relativePath == nil ? nil : "audio/mp4",
            rawTranscript: rawTranscript,
            finalText: finalText,
            speechSnapshot: ProviderProfileSnapshot(
                profileID: nil,
                name: "测试语音",
                protocolKind: .openAIAudioTranscription,
                baseURL: "https://example.test",
                modelName: "test"
            ),
            createdAt: startedAt,
            updatedAt: startedAt
        )
        try await records.create(record)
        return record
    }

    private func status(of id: UUID) async throws -> DictationStatus? {
        try await records.get(id: id)?.status
    }

    private func countRecords() async throws -> Int {
        var total = 0
        var cursor: RecordCursor?
        while true {
            let page = try await records.query(HistoryQuery(cursor: cursor))
            total += page.records.count
            guard let next = page.nextCursor else { return total }
            cursor = next
        }
    }
}
