import Foundation
@testable import OpenTypelessData
import OpenTypelessDomain
import XCTest

final class DictationRecordStoreTests: XCTestCase {
    // XCTest 夹具属性的隐式解包可选值是 XCTest 官方惯例（setUpWithError 赋值）。
    // swiftlint:disable implicitly_unwrapped_optional
    private var tempDirectory: URL!
    private var store: DictationRecordStore!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opentypeless-store-tests-\(UUID().uuidString)", isDirectory: true)
        let manager = try DatabaseManager(path: tempDirectory.appendingPathComponent("app.sqlite3").path)
        store = DictationRecordStore(pool: manager.pool)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeRecord(
        status: DictationStatus = .completed,
        startedAt: Date,
        finalText: String? = "你好，世界",
        isFavorite: Bool = false
    ) -> DictationRecord {
        DictationRecord(
            id: UUID(),
            status: status,
            startedAt: startedAt,
            finalText: finalText,
            isFavorite: isFavorite,
            speechSnapshot: ProviderProfileSnapshot(
                profileID: nil,
                name: "测试语音",
                protocolKind: .openAIAudioTranscription,
                baseURL: "https://api.example.com",
                modelName: "whisper-1"
            ),
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }

    func testCreateAndGet() async throws {
        let record = makeRecord(startedAt: Date(timeIntervalSince1970: 1_786_000_000))
        try await store.create(record)
        let fetched1 = try await store.get(id: record.id)
        let loaded = try XCTUnwrap(fetched1)
        XCTAssertEqual(loaded, record)
    }

    func testGetMissingReturnsNil() async throws {
        await XCTAssertNilAsync(try await store.get(id: UUID()))
    }

    func testSaveUpdatesFields() async throws {
        var record = makeRecord(status: .transcribed, startedAt: Date())
        try await store.create(record)
        record.isFavorite = true
        record.finalText = "最终文字"
        record.updatedAt = Date()
        try await store.save(record)
        let fetched2 = try await store.get(id: record.id)
        let loaded = try XCTUnwrap(fetched2)
        XCTAssertTrue(loaded.isFavorite)
        XCTAssertEqual(loaded.finalText, "最终文字")
    }

    func testUpdateStatusSetsAndClearsError() async throws {
        let record = makeRecord(status: .transcribing, startedAt: Date())
        try await store.create(record)

        let failure = DictationError(category: .networkUnavailable, userMessage: "网络不可用")
        try await store.updateStatus(id: record.id, status: .transcriptionFailed, error: failure, at: Date())
        let fetched3 = try await store.get(id: record.id)
        var loaded = try XCTUnwrap(fetched3)
        XCTAssertEqual(loaded.status, .transcriptionFailed)
        XCTAssertEqual(loaded.lastErrorCategory, .networkUnavailable)
        XCTAssertEqual(loaded.lastErrorMessage, "网络不可用")

        // 重试成功：新状态不带错误，旧错误必须被清除。
        try await store.updateStatus(id: record.id, status: .transcribed, error: nil, at: Date())
        let fetched4 = try await store.get(id: record.id)
        loaded = try XCTUnwrap(fetched4)
        XCTAssertEqual(loaded.status, .transcribed)
        XCTAssertNil(loaded.lastErrorCategory)
        XCTAssertNil(loaded.lastErrorMessage)
    }

    func testUpdateStatusRejectsMissingRecord() async {
        do {
            try await store.updateStatus(id: UUID(), status: .completed, error: nil, at: Date())
            XCTFail("应抛出记录不存在错误")
        } catch let error as DictationError {
            XCTAssertEqual(error.userMessage, "记录不存在")
        } catch {
            XCTFail("错误类型不符: \(error)")
        }
    }

    func testCursorPaginationIsStable() async throws {
        // 20 条记录，时间两两相同以验证双键排序稳定性。
        let base = Date(timeIntervalSince1970: 1_786_000_000)
        var created: [DictationRecord] = []
        for index in 0 ..< 20 {
            let record = makeRecord(startedAt: base.addingTimeInterval(TimeInterval(index / 2)))
            try await store.create(record)
            created.append(record)
        }
        var seen: [UUID] = []
        var cursor: RecordCursor?
        while true {
            let page = try await store.query(HistoryQuery(cursor: cursor, limit: 7))
            seen.append(contentsOf: page.records.map(\.id))
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        XCTAssertEqual(seen.count, 20)
        XCTAssertEqual(Set(seen).count, 20, "分页不得重复或遗漏记录")
    }

    func testDateRangeFilter() async throws {
        let day1 = Date(timeIntervalSince1970: 1_786_000_000)
        let day2 = day1.addingTimeInterval(86400)
        try await store.create(makeRecord(startedAt: day1))
        try await store.create(makeRecord(startedAt: day2))
        let page = try await store.query(HistoryQuery(startDate: day2, endDate: day2.addingTimeInterval(86400)))
        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(page.records.first?.startedAt, day2)
    }

    func testStatusFilters() async throws {
        try await store.create(makeRecord(status: .completed, startedAt: Date()))
        try await store.create(makeRecord(status: .transcriptionFailed, startedAt: Date()))
        try await store.create(makeRecord(status: .rewriteFailed, startedAt: Date()))
        try await store.create(makeRecord(status: .recording, startedAt: Date()))

        let success = try await store.query(HistoryQuery(statusFilter: .success))
        XCTAssertEqual(success.records.count, 1)
        XCTAssertEqual(success.records.first?.status, .completed)

        let failure = try await store.query(HistoryQuery(statusFilter: .failure))
        XCTAssertEqual(Set(failure.records.map(\.status)), [.transcriptionFailed, .rewriteFailed])
    }

    func testFavoriteFilter() async throws {
        try await store.create(makeRecord(startedAt: Date(), isFavorite: true))
        try await store.create(makeRecord(startedAt: Date(), isFavorite: false))
        let page = try await store.query(HistoryQuery(statusFilter: .favorite))
        XCTAssertEqual(page.records.count, 1)
        XCTAssertTrue(page.records.first?.isFavorite ?? false)
    }

    func testSearchMatchesFinalTextAndEscapesWildcards() async throws {
        try await store.create(makeRecord(startedAt: Date(), finalText: "完成度 100% 的任务"))
        try await store.create(makeRecord(startedAt: Date(), finalText: "普通记录"))
        let page = try await store.query(HistoryQuery(searchText: "100%"))
        XCTAssertEqual(page.records.count, 1, "百分号必须按字面匹配而非通配符")
    }

    func testFindIncompleteReturnsOnlyUnsettled() async throws {
        try await store.create(makeRecord(status: .transcribing, startedAt: Date()))
        try await store.create(makeRecord(status: .completed, startedAt: Date()))
        try await store.create(makeRecord(status: .rewriteFailed, startedAt: Date()))
        try await store.create(makeRecord(status: .ready, startedAt: Date()))
        let incomplete = try await store.findIncomplete()
        XCTAssertEqual(Set(incomplete.map(\.status)), [.transcribing, .ready])
    }

    func testAttemptsLifecycle() async throws {
        let record = makeRecord(status: .transcribing, startedAt: Date())
        try await store.create(record)
        await XCTAssertEqualAsync(try await store.attemptCount(recordID: record.id, stage: .transcription), 0)

        let attempt = RecordAttempt(
            id: UUID(),
            recordID: record.id,
            stage: .transcription,
            attemptNumber: 1,
            providerKind: .openAIAudioTranscription,
            modelName: "whisper-1",
            // 存储精度为毫秒（UTC RFC 3339 文本），用整毫秒固定时间保证往返相等。
            startedAt: Date(timeIntervalSince1970: 1_786_033_800.123),
            success: false,
            httpStatus: 429,
            errorCategory: .rateLimited,
            errorMessage: "限流"
        )
        try await store.addAttempt(attempt)
        await XCTAssertEqualAsync(try await store.attemptCount(recordID: record.id, stage: .transcription), 1)
        let attempts = try await store.attempts(recordID: record.id)
        XCTAssertEqual(attempts, [attempt])
    }

    func testDeleteCascadesAttempts() async throws {
        let record = makeRecord(startedAt: Date())
        try await store.create(record)
        try await store.addAttempt(RecordAttempt(
            id: UUID(), recordID: record.id, stage: .rewrite, attemptNumber: 1, startedAt: Date()
        ))
        try await store.delete(id: record.id)
        await XCTAssertNilAsync(try await store.get(id: record.id))
        await XCTAssertEqualAsync(try await store.attemptCount(recordID: record.id, stage: .rewrite), 0)
    }

    func testLimitIsClamped() {
        XCTAssertEqual(HistoryQuery(limit: 0).limit, 1)
        XCTAssertEqual(HistoryQuery(limit: 10000).limit, HistoryQuery.maxLimit)
    }
}
