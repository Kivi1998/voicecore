import Charts
import OpenTypelessApplication
import OpenTypelessDomain
import SwiftUI

/// 首页视图模型（UI-003）：统计、七日趋势、当前模型、最近记录。
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var summary: StatisticsSummary?
    @Published var trend: [DailyUnits] = []
    @Published var speechProfileName: String?
    @Published var rewriteProfileName: String?
    @Published var recentRecords: [DictationRecord] = []
    @Published var errorMessage: String?

    private let statistics: StatisticsService
    private let records: any DictationRecordRepository
    private let profiles: any ProviderProfileRepository

    init(
        statistics: StatisticsService,
        records: any DictationRecordRepository,
        profiles: any ProviderProfileRepository
    ) {
        self.statistics = statistics
        self.records = records
        self.profiles = profiles
    }

    func reload() async {
        errorMessage = nil
        do {
            async let summaryTask = statistics.summary()
            async let trendTask = statistics.dailyTrend(days: 7)
            async let recentTask = records.query(HistoryQuery(limit: 5))
            let (summary, trend, recent) = try await (summaryTask, trendTask, recentTask)
            self.summary = summary
            self.trend = trend
            self.recentRecords = recent.records
            speechProfileName = try await profiles.defaultProfile(purpose: .speech)?.name
            rewriteProfileName = try await profiles.defaultProfile(purpose: .rewrite)?.name
        } catch {
            errorMessage = "统计数据读取失败，请重试。"
        }
    }
}

/// 首页（UI-003）：今日/本周/累计、七日趋势、当前模型、最近记录。
/// 空数据展示 0 与空态，绝不出现假数字。
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel

    init(composition: AppComposition) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(
            statistics: composition.statistics,
            records: composition.records,
            profiles: composition.profiles
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                header
                statsRow
                trendSection
                modelSection
                recentSection
            }
            .padding(DS.Spacing.xxl)
        }
        .navigationTitle("首页")
        .task {
            await viewModel.reload()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("今天想说点什么？")
                .font(DS.Font.title)
            Text("按 ⌥Space 开始录音，再按一次结束。")
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: DS.Spacing.md) {
            StatCard(title: "今日", value: viewModel.summary?.todayUnits ?? 0, unit: "字")
            StatCard(title: "本周", value: viewModel.summary?.weekUnits ?? 0, unit: "字")
            StatCard(title: "累计", value: viewModel.summary?.totalUnits ?? 0, unit: "字")
        }
        .accessibilityElement(children: .contain)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("近七日")
                .font(DS.Font.headline)
            Chart(viewModel.trend, id: \.dayStart) { day in
                BarMark(
                    x: .value("日期", day.dayStart, unit: .day),
                    y: .value("字数", day.units)
                )
            }
            .frame(height: 160)
            .accessibilityLabel("近七日口述字数趋势")
            .accessibilityValue(trendAccessibilitySummary)
        }
    }

    /// 趋势图 VoiceOver 摘要（不仅靠图形表达）。
    private var trendAccessibilitySummary: String {
        viewModel.trend
            .map { "\($0.dayStart.formatted(.dateTime.month().day()))：\($0.units) 字" }
            .joined(separator: "，")
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("当前模型")
                .font(DS.Font.headline)
            LabeledContent("语音识别", value: viewModel.speechProfileName ?? "未配置")
            LabeledContent("文字改写", value: viewModel.rewriteProfileName ?? "已关闭或未配置")
        }
        .foregroundStyle(.secondary)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("最近记录")
                .font(DS.Font.headline)
            if viewModel.recentRecords.isEmpty {
                Text("还没有口述记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.recentRecords) { record in
                    RecentRecordRow(record: record)
                }
            }
        }
    }
}

/// 最近记录行。
struct RecentRecordRow: View {
    let record: DictationRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(record.finalText ?? record.rawTranscript ?? "（无文字）")
                .lineLimit(1)
            Spacer()
            RecordStatusBadge(status: record.status)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 状态徽标：图标＋文字＋语义色（颜色不是唯一通道）。
struct RecordStatusBadge: View {
    let status: DictationStatus

    var body: some View {
        Label(text, systemImage: symbol)
            .font(DS.Font.caption)
            .foregroundStyle(color)
            .accessibilityLabel("状态：\(text)")
    }

    private var text: String {
        RecordStatusText.text(for: status)
    }

    private var symbol: String {
        status.isSettled && !status.isFailure ? "checkmark.circle.fill"
            : status.isFailure ? "exclamationmark.circle.fill"
            : "ellipsis.circle"
    }

    private var color: Color {
        status.isFailure ? DS.Color.failure
            : status.isSettled ? DS.Color.success
            : DS.Color.secondaryText
    }
}
