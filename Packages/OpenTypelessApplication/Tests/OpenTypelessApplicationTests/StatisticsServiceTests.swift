import Foundation
import OpenTypelessData
import OpenTypelessDomain
import XCTest
@testable import OpenTypelessApplication

/// 统计聚合服务测试（CORE-006）。
///
/// 固定「当前时间」与固定时区（GMT+8）日历，验证跨日、跨周（周一起）
/// 与时区边界的聚合正确性。
final class StatisticsServiceTests: XCTestCase {
    private var tempDir: URL!
    private var records: DictationRecordStore!

    /// 固定时区 GMT+8，覆盖与 UTC 不同日的场景。
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }()

    /// 固定当前时间：2026-08-07 12:00（GMT+8，周五）。
    private var fixedNow: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12))!
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("statistics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = try DatabaseManager(path: tempDir.appendingPathComponent("test.sqlite").path)
        records = DictationRecordStore(pool: manager.pool)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeService() -> StatisticsService {
        StatisticsService(records: records, calendar: calendar, now: { [fixedNow] in fixedNow })
    }

    func testSummaryAggregatesTodayWeekAndTotal() async throws {
        // 今天 09:00：5 单位。
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 7, hour: 9), units: 5)
        // 本周一 10:00：7 单位（计入本周，不计今日）。
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 3, hour: 10), units: 7)
        // 上周日 22:00：11 单位（不计本周，计入累计）。
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 2, hour: 22), units: 11)

        let summary = try await makeService().summary()
        XCTAssertEqual(summary.todayUnits, 5)
        XCTAssertEqual(summary.weekUnits, 5 + 7)
        XCTAssertEqual(summary.totalUnits, 5 + 7 + 11)
        XCTAssertEqual(summary.totalRecords, 3)
    }

    func testWeekStartsOnMonday() async throws {
        // 本周一 00:30 计入本周；上周日 23:30 不计。
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 3, hour: 0, minute: 30), units: 3)
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 2, hour: 23, minute: 30), units: 9)

        let summary = try await makeService().summary()
        XCTAssertEqual(summary.weekUnits, 3)
        XCTAssertEqual(summary.totalUnits, 12)
    }

    func testLocalTimezoneDayBoundary() async throws {
        // UTC 2026-08-06 16:30 = 本地 2026-08-07 00:30，属于「今天」。
        let utcDate = Date(timeIntervalSince1970: 1_786_033_800) // 2026-08-06 16:30 UTC
        try await insertRecord(utcDate: utcDate, units: 4)

        let summary = try await makeService().summary()
        XCTAssertEqual(summary.todayUnits, 4)

        let trend = try await makeService().dailyTrend(days: 2)
        XCTAssertEqual(trend.count, 2)
        // 落在趋势的最后一天（今天）。
        XCTAssertEqual(trend.last?.units, 4)
        XCTAssertEqual(trend.first?.units, 0)
    }

    func testDailyTrendZeroFillsAndOrdersAscending() async throws {
        // 6 天前与今天有记录，中间补零。
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 1, hour: 8), units: 6)
        try await insertRecord(localDay: DateComponents(year: 2026, month: 8, day: 7, hour: 8), units: 2)

        let trend = try await makeService().dailyTrend(days: 7)
        XCTAssertEqual(trend.count, 7)
        XCTAssertEqual(trend.map(\.units), [6, 0, 0, 0, 0, 0, 2])
        // 按时间升序且最后一天是今天零点。
        XCTAssertEqual(trend.last?.dayStart, calendar.startOfDay(for: fixedNow))
    }

    func testRecordsWithoutFinalTextAreExcluded() async throws {
        try await insertRecord(
            localDay: DateComponents(year: 2026, month: 8, day: 7, hour: 9),
            units: 8,
            finalText: nil
        )

        let summary = try await makeService().summary()
        XCTAssertEqual(summary.todayUnits, 0)
        XCTAssertEqual(summary.totalRecords, 0)
    }

    // MARK: - 工具

    /// 按本地时间组件插入记录。
    private func insertRecord(
        localDay: DateComponents,
        units: Int64,
        finalText: String? = "成品"
    ) async throws {
        let date = calendar.date(from: localDay)!
        try await insertRecord(utcDate: date, units: units, finalText: finalText)
    }

    private func insertRecord(utcDate: Date, units: Int64, finalText: String? = "成品") async throws {
        let record = DictationRecord(
            id: UUID(),
            status: finalText == nil ? .transcriptionFailed : .completed,
            startedAt: utcDate,
            durationMs: 1000,
            finalText: finalText,
            countUnits: units,
            speechSnapshot: ProviderProfileSnapshot(
                profileID: nil,
                name: "测试语音",
                protocolKind: .openAIAudioTranscription,
                baseURL: "https://example.test",
                modelName: "test"
            ),
            createdAt: utcDate,
            updatedAt: utcDate
        )
        try await records.create(record)
    }
}
