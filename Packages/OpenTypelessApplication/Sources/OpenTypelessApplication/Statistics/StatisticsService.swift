import Foundation
import OpenTypelessDomain

/// 统计总览（仪表盘展示）。
public struct StatisticsSummary: Sendable, Equatable {
    /// 今日单位数（本地时区自然日）。
    public var todayUnits: Int64
    /// 本周单位数（周一起，本地时区）。
    public var weekUnits: Int64
    /// 累计单位数。
    public var totalUnits: Int64
    /// 累计记录条数（已生成最终文字）。
    public var totalRecords: Int

    public init(todayUnits: Int64, weekUnits: Int64, totalUnits: Int64, totalRecords: Int) {
        self.todayUnits = todayUnits
        self.weekUnits = weekUnits
        self.totalUnits = totalUnits
        self.totalRecords = totalRecords
    }

    public static let zero = StatisticsSummary(todayUnits: 0, weekUnits: 0, totalUnits: 0, totalRecords: 0)
}

/// 单日单位数（趋势图数据点）。
public struct DailyUnits: Sendable, Equatable {
    /// 当日零点（本地时区）。
    public var dayStart: Date
    public var units: Int64

    public init(dayStart: Date, units: Int64) {
        self.dayStart = dayStart
        self.units = units
    }
}

/// 统计能力协议（仪表盘与菜单栏展示）。
public protocol StatisticsProviding: Sendable {
    /// 今日 / 本周（周一起）/ 累计总览。
    func summary() async throws -> StatisticsSummary

    /// 最近 N 日（含今日）的逐日单位数，无记录日期补零，按时间升序。
    func dailyTrend(days: Int) async throws -> [DailyUnits]
}

/// 统计聚合服务（CORE-006）。
///
/// - 计数规则由 `UnitCounter` 统一（中文按字、英文按词、标点空白不计），
///   在最终文字保存时写入记录；
/// - 「今日」「本周」按本地时区取边界后换算 UTC 查询，跨周与时区正确；
/// - 只统计已生成最终文字（`final_text` 非空）的记录；
/// - 趋势按记录开始时间在本地时区分桶，不在 SQL 中做时区换算。
public struct StatisticsService: StatisticsProviding {
    private let records: any DictationRecordRepository
    /// 本地日历（测试可注入固定时区）；服务内部复制后固定周一为每周首日。
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        records: any DictationRecordRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.records = records
        self.calendar = calendar
        self.now = now
    }

    public func summary() async throws -> StatisticsSummary {
        var calendar = self.calendar
        calendar.firstWeekday = 2 // 周一
        let current = now()
        let todayStart = calendar.startOfDay(for: current)
        // 本周起点：包含当前日期的周区间的第一天（周一）。
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: current)?.start ?? todayStart

        async let today = records.unitsSummary(from: todayStart, to: nil)
        async let week = records.unitsSummary(from: weekStart, to: nil)
        async let total = records.unitsSummary(from: nil, to: nil)

        let (todaySummary, weekSummary, totalSummary) = try await (today, week, total)
        return StatisticsSummary(
            todayUnits: todaySummary.totalUnits,
            weekUnits: weekSummary.totalUnits,
            totalUnits: totalSummary.totalUnits,
            totalRecords: totalSummary.recordCount
        )
    }

    public func dailyTrend(days: Int) async throws -> [DailyUnits] {
        let count = max(1, days)
        let calendar = self.calendar
        let todayStart = calendar.startOfDay(for: now())
        guard let rangeStart = calendar.date(byAdding: .day, value: -(count - 1), to: todayStart) else {
            return []
        }

        let entries = try await records.unitEntries(from: rangeStart, to: nil)
        var buckets: [Date: Int64] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.startedAt)
            buckets[day, default: 0] += entry.units
        }

        var result: [DailyUnits] = []
        result.reserveCapacity(count)
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: rangeStart) else { continue }
            result.append(DailyUnits(dayStart: day, units: buckets[day] ?? 0))
        }
        return result
    }
}
