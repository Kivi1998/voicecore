import Foundation
import XCTest
@testable import OpenTypelessApplication
import OpenTypelessDomain
import OpenTypelessData

/// 记录生命周期、导出与存储统计测试（DATA-006）。
final class RecordLifecycleTests: XCTestCase {
    private var tempDir: URL!
    private var records: DictationRecordStore!
    private var audioFiles: FileAudioFileStore!
    private var recordingsRoot: URL!
    private var lifecycle: RecordLifecycleService!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifecycle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)
        records = DictationRecordStore(pool: manager.pool)
        recordingsRoot = tempDir.appendingPathComponent("recordings", isDirectory: true)
        audioFiles = FileAudioFileStore(recordingsRoot: recordingsRoot)
        lifecycle = RecordLifecycleService(records: records, audioFiles: audioFiles)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 删除编排

    func testDeleteRecordRemovesDatabaseAudioAndAttempts() async throws {
        let record = try await insertRecord(withAudio: true, isFavorite: true)
        try await records.addAttempt(RecordAttempt(
            id: UUID(),
            recordID: record.id,
            stage: .transcription,
            attemptNumber: 1,
            startedAt: Date()
        ))

        let report = try await lifecycle.deleteRecord(id: record.id)

        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.freedAudioBytes, 64)
        XCTAssertNil(try await records.get(id: record.id))
        XCTAssertEqual(try await records.attempts(recordID: record.id).count, 0)
        let path = try XCTUnwrap(record.audioRelativePath)
        XCTAssertFalse(try audioFiles.info(relativePath: path).exists)
    }

    func testDeleteRecordWithoutAudioSucceeds() async throws {
        let record = try await insertRecord(withAudio: false)
        let report = try await lifecycle.deleteRecord(id: record.id)
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.freedAudioBytes, 0)
    }

    func testDeleteRecordWithMissingAudioStillCompletes() async throws {
        // 数据库有路径但文件已不存在（用户手动删过）。
        let record = try await insertRecord(withAudio: false, audioPath: "2026/08/07/\(UUID().uuidString).m4a")
        let report = try await lifecycle.deleteRecord(id: record.id)
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.missingAudioCount, 1)
    }

    func testDeleteUnknownRecordIsIdempotent() async throws {
        let report = try await lifecycle.deleteRecord(id: UUID())
        XCTAssertEqual(report.deletedCount, 0)
    }

    func testBatchDeleteRemovesAll() async throws {
        let a = try await insertRecord(withAudio: true)
        let b = try await insertRecord(withAudio: true)
        let keep = try await insertRecord(withAudio: true)

        let report = try await lifecycle.deleteRecords(ids: [a.id, b.id])
        XCTAssertEqual(report.deletedCount, 2)
        XCTAssertEqual(try await records.recordCount(), 1)
        XCTAssertNotNil(try await records.get(id: keep.id))
    }

    // MARK: - 导出

    func testExportContainsRecordsAndNoSecrets() async throws {
        _ = try await insertRecord(withAudio: false, finalText: "你好世界")
        _ = try await insertRecord(withAudio: false, finalText: "hello world")

        let exportURL = tempDir.appendingPathComponent("export/history.json")
        let service = HistoryExportService(records: records)
        let report = try await service.export(to: exportURL)

        XCTAssertEqual(report.recordCount, 2)
        let data = try Data(contentsOf: exportURL)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("你好世界"))
        XCTAssertTrue(text.contains("hello world"))
        // 默认导出不含密钥与文件路径字段。
        XCTAssertFalse(text.contains("api_key"))
        XCTAssertFalse(text.contains("apiKey"))
        XCTAssertFalse(text.contains("audioRelativePath"))
        XCTAssertFalse(text.contains("audio_rel_path"))

        // 可解析回信封结构。
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(HistoryExportEnvelope.self, from: data)
        XCTAssertEqual(envelope.formatVersion, HistoryExportService.formatVersion)
        XCTAssertEqual(envelope.recordCount, 2)
        // 按时间升序。
        XCTAssertLessThanOrEqual(envelope.records[0].startedAt, envelope.records[1].startedAt)
    }

    func testExportIsAtomicAndOverwrites() async throws {
        _ = try await insertRecord(withAudio: false)
        let exportURL = tempDir.appendingPathComponent("history.json")
        let service = HistoryExportService(records: records)

        _ = try await service.export(to: exportURL)
        _ = try await service.export(to: exportURL) // 覆盖已有文件
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        // 无残留临时文件。
        let siblings = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(siblings.contains { $0.hasPrefix(".") && $0.contains(".tmp-") })
    }

    // MARK: - 存储统计

    func testStorageUsageSumsAudioAndCountsRecords() async throws {
        _ = try await insertRecord(withAudio: true)
        _ = try await insertRecord(withAudio: true)

        let service = StorageStatisticsService(
            records: records,
            audioFiles: audioFiles,
            databaseSizeBytes: { 4_096 }
        )
        let usage = try await service.usage()

        XCTAssertEqual(usage.audioBytes, 128)
        XCTAssertEqual(usage.databaseBytes, 4_096)
        XCTAssertEqual(usage.recordCount, 2)
        XCTAssertEqual(usage.totalBytes, 128 + 4_096)
    }

    // MARK: - 工具

    @discardableResult
    private func insertRecord(
        withAudio: Bool,
        isFavorite: Bool = false,
        finalText: String? = "成品文字",
        audioPath: String? = nil
    ) async throws -> DictationRecord {
        let startedAt = Date()
        let recordID = UUID()
        var path = audioPath
        if withAudio {
            let prepared = try audioFiles.prepareDestination(recordID: recordID, startedAt: startedAt, fileExtension: "m4a")
            let writer = try audioFiles.openForWriting(relativePath: prepared)
            try writer.append(Data(repeating: 0x63, count: 64))
            try writer.close()
            _ = try audioFiles.finalize(relativePath: prepared)
            path = prepared
        }
        let record = DictationRecord(
            id: recordID,
            status: .completed,
            startedAt: startedAt,
            audioRelativePath: path,
            audioMimeType: path == nil ? nil : "audio/mp4",
            finalText: finalText,
            countUnits: finalText.map { UnitCounter.count($0) } ?? 0,
            isFavorite: isFavorite,
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
}
