import AppKit
import OpenTypelessApplication
import OpenTypelessDomain
import SwiftUI
import UniformTypeIdentifiers

/// 历史视图模型（HIST-001/002/003/004）。
///
/// 组合筛选＋游标分页；每页追加，禁止全量加载。
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var statusFilter: HistoryStatusFilter = .all
    @Published var startDate: Date?
    @Published var endDate: Date?
    @Published private(set) var records: [DictationRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published var errorMessage: String?
    @Published var recordPendingDeletion: DictationRecord?
    @Published var toastMessage: ToastMessage?

    private let repository: any DictationRecordRepository
    private let lifecycle: RecordLifecycleService
    private let clipboard: any ClipboardService
    private let orchestrator: DictationOrchestrator
    private let audioURLResolver: (String) throws -> URL
    private var nextCursor: RecordCursor?

    init(composition: AppComposition) {
        repository = composition.records
        lifecycle = composition.lifecycle
        clipboard = composition.clipboard
        orchestrator = composition.orchestrator
        audioURLResolver = { relativePath in
            try composition.paths.resolveRecording(relativePath: relativePath)
        }
    }

    /// 按日期分组（本地时区自然日，降序）。
    var groupedByDay: [(day: Date, records: [DictationRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, records: $0.value.sorted { $0.startedAt > $1.startedAt }) }
    }

    func reload() async {
        nextCursor = nil
        records = []
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let page = try await repository.query(HistoryQuery(
                startDate: startDate,
                endDate: endDate.map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 },
                statusFilter: statusFilter,
                searchText: searchText.isEmpty ? nil : searchText,
                cursor: nextCursor
            ))
            records.append(contentsOf: page.records)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = "历史读取失败，请重试。"
        }
    }

    // MARK: - 操作

    func copyText(_ record: DictationRecord) async {
        guard let text = record.finalText ?? record.rawTranscript else { return }
        await clipboard.writeText(text)
        toastMessage = ToastMessage(kind: .success, text: "已复制到剪贴板")
    }

    func toggleFavorite(_ record: DictationRecord) async {
        var updated = record
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        do {
            try await repository.save(updated)
            replaceInList(updated)
            toastMessage = ToastMessage(
                kind: .info,
                text: updated.isFavorite ? "已收藏" : "已取消收藏"
            )
        } catch {
            errorMessage = "收藏更新失败。"
        }
    }

    func confirmDeletion(_ record: DictationRecord) {
        recordPendingDeletion = record
    }

    func deletePending() async {
        guard let record = recordPendingDeletion else { return }
        recordPendingDeletion = nil
        do {
            try await lifecycle.deleteRecord(id: record.id)
            records.removeAll { $0.id == record.id }
        } catch {
            errorMessage = "删除失败，请重试。"
        }
    }

    /// 下载录音：复制到用户选择的位置（NSSavePanel）。
    func downloadAudio(_ record: DictationRecord) async {
        guard let path = record.audioRelativePath,
              let source = try? audioURLResolver(path),
              FileManager.default.fileExists(atPath: source.path) else {
            errorMessage = "录音文件不存在。"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.allowedContentTypes = [UTType(filenameExtension: "m4a") ?? .audio]
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            toastMessage = ToastMessage(kind: .success, text: "录音已导出")
        } catch {
            errorMessage = "导出录音失败。"
        }
    }

    func playAudio(_ record: DictationRecord) {
        guard let path = record.audioRelativePath,
              let url = try? audioURLResolver(path) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 重试（HIST-004）

    func retry(_ record: DictationRecord) async {
        do {
            switch record.status {
            case .transcriptionFailed:
                try await orchestrator.retryTranscription(recordID: record.id)
            case .rewriteFailed:
                try await orchestrator.retryRewrite(recordID: record.id)
            case .injectionFailed:
                try await orchestrator.retryInjection(recordID: record.id)
            default:
                return
            }
            await reloadAfterSettle(recordID: record.id)
        } catch let error as DictationError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "重试发起失败。"
        }
    }

    /// 轮询至停滞后刷新单条。
    private func reloadAfterSettle(recordID: UUID) async {
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let updated = try? await repository.get(id: recordID), updated.status.isSettled {
                replaceInList(updated)
                return
            }
        }
    }

    private func replaceInList(_ updated: DictationRecord) {
        if let index = records.firstIndex(where: { $0.id == updated.id }) {
            records[index] = updated
        }
    }
}

/// 历史页面（HIST-002）：日期分组列表、搜索与筛选、详情展开。
struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    @State private var expandedID: UUID?

    init(composition: AppComposition) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(composition: composition))
    }

    var body: some View {
        List {
            ForEach(viewModel.groupedByDay, id: \.day) { group in
                Section(group.day.formatted(.dateTime.year().month().day().weekday())) {
                    ForEach(group.records) { record in
                        HistoryRecordRow(
                            record: record,
                            isExpanded: expandedID == record.id,
                            onToggle: { expandedID = expandedID == record.id ? nil : record.id },
                            actions: viewModel
                        )
                        .onAppear {
                            // 滚动到接近末尾时加载下一页。
                            if record.id == viewModel.records.last?.id, viewModel.hasMore {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
            }
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("历史记录")
        .searchable(text: $viewModel.searchText, prompt: "搜索原始或最终文字")
        .safeAreaInset(edge: .top) {
            HStack {
                DateRangeFilter(startDate: $viewModel.startDate, endDate: $viewModel.endDate)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .toast($viewModel.toastMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("状态", selection: $viewModel.statusFilter) {
                    Text("全部").tag(HistoryStatusFilter.all)
                    Text("成功").tag(HistoryStatusFilter.success)
                    Text("失败").tag(HistoryStatusFilter.failure)
                    Text("收藏").tag(HistoryStatusFilter.favorite)
                }
                .accessibilityLabel("按状态筛选")
            }
        }
        .overlay {
            if let message = viewModel.errorMessage {
                ErrorStateView(message: message) {
                    Task { await viewModel.reload() }
                }
            } else if viewModel.records.isEmpty, !viewModel.isLoading {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "暂无记录",
                    message: "按 ⌥Space 开始第一次口述。"
                )
            }
        }
        .task(id: viewModel.searchText) {
            // 搜索输入防抖。
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.reload()
        }
        .task(id: viewModel.statusFilter) {
            await viewModel.reload()
        }
        .task(id: viewModel.startDate) {
            await viewModel.reload()
        }
        .task(id: viewModel.endDate) {
            await viewModel.reload()
        }
        .alert("删除这条记录？", isPresented: deletionBinding, presenting: viewModel.recordPendingDeletion) { _ in
            Button("删除", role: .destructive) {
                Task { await viewModel.deletePending() }
            }
            Button("取消", role: .cancel) {
                viewModel.recordPendingDeletion = nil
            }
        } message: { record in
            Text("将同时删除数据库记录与录音文件，此操作不可撤销。")
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.recordPendingDeletion != nil },
            set: { if !$0 { viewModel.recordPendingDeletion = nil } }
        )
    }
}

/// 历史记录行：摘要＋展开详情与操作（HIST-003/004）。
struct HistoryRecordRow: View {
    let record: DictationRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let actions: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.startedAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text(record.finalText ?? record.rawTranscript ?? "（无文字）")
                        .lineLimit(isExpanded ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("已收藏")
                    }
                    RecordStatusBadge(status: record.status)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                detail
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let failureStage = RecordStatusText.failureStageText(for: record.status) {
                Label(
                    "\(failureStage)失败：\(record.lastErrorMessage ?? "未知原因")",
                    systemImage: "exclamationmark.circle"
                )
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.failure)
            }
            if let raw = record.rawTranscript, raw != record.finalText {
                LabeledContent("原始文字") {
                    Text(raw).textSelection(.enabled)
                }
            }
            if let final = record.finalText {
                LabeledContent("最终文字") {
                    Text(final).textSelection(.enabled)
                }
            }
            LabeledContent("语音模型", value: record.speechSnapshot.name)
            if let rewrite = record.rewriteSnapshot {
                LabeledContent("改写模型", value: rewrite.name)
            }
            if record.durationMs > 0 {
                LabeledContent("时长", value: String(format: "%.1f 秒", Double(record.durationMs) / 1_000))
            }

            actionBar
        }
        .padding(.leading, 56)
    }

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.lg) {
            Button {
                Task { await actions.copyText(record) }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(record.finalText == nil && record.rawTranscript == nil)

            Button {
                actions.playAudio(record)
            } label: {
                Label("播放", systemImage: "play.circle")
            }
            .disabled(record.audioRelativePath == nil)

            Button {
                Task { await actions.downloadAudio(record) }
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .disabled(record.audioRelativePath == nil)

            Button {
                Task { await actions.toggleFavorite(record) }
            } label: {
                Label(record.isFavorite ? "取消收藏" : "收藏",
                      systemImage: record.isFavorite ? "star.fill" : "star")
            }

            if retryTitle != nil {
                Button {
                    Task { await actions.retry(record) }
                } label: {
                    Label(retryTitle!, systemImage: "arrow.clockwise")
                }
            }

            Spacer()

            Button(role: .destructive) {
                actions.confirmDeletion(record)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .font(DS.Font.callout)
        .buttonStyle(.borderless)
    }

    /// 失败阶段的就近重试文案（HIST-004：改写失败不重复上传音频）。
    private var retryTitle: String? {
        switch record.status {
        case .transcriptionFailed: "重新识别"
        case .rewriteFailed: "仅重新改写"
        case .injectionFailed: "再次输入"
        default: nil
        }
    }
}
