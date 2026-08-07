import AppKit
import OpenTypelessApplication
import OpenTypelessDomain
import SwiftUI

/// 设置视图模型（SET-001/SET-004）。
@MainActor
final class SettingsViewModel: ObservableObject {
    // 通用（SET-001）
    @Published var rewriteEnabled = true
    @Published var autoInsert = true
    @Published var restoreClipboard = true
    @Published var interactionSound = true
    @Published var launchAtLogin = false
    @Published var showInDock = true

    // 数据与存储（SET-004）
    @Published var storageUsage: StorageUsage?
    @Published var statusMessage: String?
    @Published var isCleanupConfirmPresented = false
    @Published var cleanupOlderThanDays = 90

    private let settings: any AppSettingsRepository
    private let composition: AppComposition

    /// 暴露组合根给子视图（模型配置页需要）。
    var compositionForChildren: AppComposition { composition }

    init(composition: AppComposition) {
        self.composition = composition
        settings = composition.settings
    }

    func load() async {
        rewriteEnabled = (try? await settings.bool(forKey: .rewriteEnabled, default: true)) ?? true
        autoInsert = (try? await settings.bool(forKey: .autoInsert, default: true)) ?? true
        restoreClipboard = (try? await settings.bool(forKey: .restoreClipboard, default: true)) ?? true
        interactionSound = (try? await settings.bool(forKey: .interactionSound, default: true)) ?? true
        launchAtLogin = await composition.autostart.isEnabled()
        showInDock = (try? await settings.bool(forKey: .showInDock, default: true)) ?? true
        storageUsage = try? await composition.storage.usage()
    }

    func save(_ key: AppSettingKey, value: Bool) async {
        try? await settings.setBool(value, forKey: key)
        if key == .launchAtLogin {
            try? await composition.autostart.setEnabled(value)
        }
        if key == .showInDock {
            NSApp.setActivationPolicy(value ? .regular : .accessory)
        }
    }

    // MARK: - 数据与存储

    func openDataDirectory() {
        NSWorkspace.shared.open(composition.paths.dataRoot)
    }

    /// 导出历史（默认不含密钥；提示策略由导出服务保证）。
    func exportHistory() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "opentypeless-history.json"
        panel.allowedContentTypes = [.json]
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            let report = try await composition.export.export(to: url)
            statusMessage = "已导出 \(report.recordCount) 条记录（不含任何密钥）。"
        } catch {
            statusMessage = "导出失败，请重试。"
        }
    }

    /// 手动清理：删除指定天数之前的记录（界面已二次确认）。
    func cleanupOldRecords() async {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -cleanupOlderThanDays,
            to: Date()
        ) else { return }
        do {
            // 游标分页收集范围外记录的 ID（范围由用户明确选择）。
            var ids: [UUID] = []
            var cursor: RecordCursor?
            while true {
                let page = try await composition.records.query(HistoryQuery(
                    endDate: cutoff,
                    cursor: cursor,
                    limit: HistoryQuery.maxLimit
                ))
                ids.append(contentsOf: page.records.map(\.id))
                guard let next = page.nextCursor else { break }
                cursor = next
            }
            let report = try await composition.lifecycle.deleteRecords(ids: ids)
            statusMessage = "已清理 \(report.deletedCount) 条 \(cleanupOlderThanDays) 天前的记录。"
            storageUsage = try? await composition.storage.usage()
        } catch {
            statusMessage = "清理失败，请重试。"
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 设置页面（原生 Form 分组；模型配置页见 ProviderSettingsView）。
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(composition: AppComposition) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(composition: composition))
    }

    var body: some View {
        TabView {
            Form {
                generalSection
                outputSection
            }
            .formStyle(.grouped)
            .tabItem { Label(L10n.Settings.general, systemImage: "gear") }

            ProviderSettingsView(composition: viewModelComposition)
                .tabItem { Label(L10n.Settings.providers, systemImage: "cpu") }

            Form {
                storageSection
            }
            .formStyle(.grouped)
            .tabItem { Label(L10n.Settings.storage, systemImage: "internaldrive") }
        }
        .padding(DS.Spacing.xl)
        .task {
            await viewModel.load()
        }
    }

    /// 暴露组合根给子视图（StateObject 持有安全）。
    private var viewModelComposition: AppComposition {
        viewModel.compositionForChildren
    }

    // MARK: - 通用

    private var generalSection: some View {
        Section("快捷键与录音") {
            LabeledContent("全局快捷键", value: "⌥Space")
            Toggle("登录时自动启动", isOn: binding(.launchAtLogin))
            Toggle("在程序坞显示图标", isOn: binding(.showInDock))
            Toggle("交互提示音", isOn: binding(.interactionSound))
        }
    }

    private var outputSection: some View {
        Section("输出") {
            Toggle("启用文字改写", isOn: binding(.rewriteEnabled))
            Toggle("自动写入当前输入框", isOn: binding(.autoInsert))
            Toggle("输入后恢复原剪贴板", isOn: binding(.restoreClipboard))
                .disabled(!viewModel.autoInsert)
        }
    }

    // MARK: - 数据与存储（SET-004）

    private var storageSection: some View {
        Section("数据与存储") {
            LabeledContent("录音永久保留") {
                Text("应用不会自动删除任何录音，只有你可以手动删除。")
                    .font(DS.Font.callout)
                    .foregroundStyle(.secondary)
            }
            if let usage = viewModel.storageUsage {
                LabeledContent("录音占用", value: SettingsViewModel.formatBytes(usage.audioBytes))
                LabeledContent("数据库占用", value: SettingsViewModel.formatBytes(usage.databaseBytes))
                LabeledContent(L10n.Page.history, value: "\(usage.recordCount) 条")
            }
            Button("打开数据目录", action: viewModel.openDataDirectory)

            Button("导出历史…") {
                Task { await viewModel.exportHistory() }
            }

            HStack {
                Stepper("清理 \(viewModel.cleanupOlderThanDays) 天前的记录",
                        value: $viewModel.cleanupOlderThanDays, in: 7...365)
                Button("清理…", role: .destructive) {
                    viewModel.isCleanupConfirmPresented = true
                }
            }
            .confirmationDialog(
                "确认清理？",
                isPresented: $viewModel.isCleanupConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("删除 \(viewModel.cleanupOlderThanDays) 天前的全部记录与录音", role: .destructive) {
                    Task { await viewModel.cleanupOldRecords() }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text("此操作不可撤销，且是唯一的批量删除入口；应用绝不自动清理。")
            }

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(DS.Font.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ key: AppSettingKey) -> Binding<Bool> {
        Binding(
            get: {
                switch key {
                case .rewriteEnabled: viewModel.rewriteEnabled
                case .autoInsert: viewModel.autoInsert
                case .restoreClipboard: viewModel.restoreClipboard
                case .interactionSound: viewModel.interactionSound
                case .launchAtLogin: viewModel.launchAtLogin
                case .showInDock: viewModel.showInDock
                default: false
                }
            },
            set: { value in
                switch key {
                case .rewriteEnabled: viewModel.rewriteEnabled = value
                case .autoInsert: viewModel.autoInsert = value
                case .restoreClipboard: viewModel.restoreClipboard = value
                case .interactionSound: viewModel.interactionSound = value
                case .launchAtLogin: viewModel.launchAtLogin = value
                case .showInDock: viewModel.showInDock = value
                default: break
                }
                Task { await viewModel.save(key, value: value) }
            }
        )
    }
}
