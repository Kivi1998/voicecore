import AppKit
import Foundation
import OpenTypelessApplication
import OpenTypelessData
import OpenTypelessDomain
import OpenTypelessPlatform
import OpenTypelessProviders

/// 应用组合根（@MainActor 单例，App 入口构造一次）。
///
/// 负责：路径 → 数据库 → 仓储 → 平台服务 → 编排器 → 菜单栏/悬浮条 →
/// 快捷键接线。密钥只在 `StoreProviderFactory` 内流动。
@MainActor
final class AppComposition: ObservableObject {
    let paths: AppPathsService
    let database: DatabaseManager
    let records: DictationRecordStore
    let audioFiles: FileAudioFileStore
    let dictionary: DictionaryStore
    let profiles: ProviderProfileStore
    let settings: AppSettingsStore

    let clipboard: SystemClipboardService
    let injector: AccessibilityTextInjector
    let permissions: SystemPermissionService
    let autostart: SMAppLoginItemService
    let capture: AVAudioCaptureService
    let shortcut: CarbonGlobalShortcut

    let orchestrator: DictationOrchestrator
    let statistics: StatisticsService
    let lifecycle: RecordLifecycleService
    let export: HistoryExportService
    let storage: StorageStatisticsService
    let recovery: StartupRecoveryService

    private(set) var menuBar: StatusItemMenuBarController!
    private(set) var overlay: RecordingOverlayController!
    private var shortcutEventTask: Task<Void, Never>?
    private var levelEventTask: Task<Void, Never>?

    /// 由 App 场景注入的窗口动作（菜单栏转发）。
    var openMainWindowHandler: @Sendable () -> Void = {}
    var openHistoryHandler: @Sendable () -> Void = {}
    var openSettingsHandler: @Sendable () -> Void = {}

    /// 菜单栏请求的页面导航（RootView 消费后置空）。
    @Published var requestedPage: AppPage?

    init(bundleIdentifier: String) throws {
        let paths = try AppPathsService(bundleIdentifier: bundleIdentifier)
        self.paths = paths
        let database = try DatabaseManager(
            path: paths.dataRoot.appendingPathComponent("opentypeless.sqlite").path
        )
        self.database = database

        records = DictationRecordStore(pool: database.pool)
        let audioFiles = FileAudioFileStore(recordingsRoot: paths.recordingsRoot)
        self.audioFiles = audioFiles
        dictionary = DictionaryStore(pool: database.pool)
        profiles = ProviderProfileStore(pool: database.pool)
        settings = AppSettingsStore(pool: database.pool)

        clipboard = SystemClipboardService()
        injector = AccessibilityTextInjector(clipboard: clipboard)
        permissions = SystemPermissionService()
        autostart = SMAppLoginItemService()
        capture = AVAudioCaptureService(
            partialURLResolver: { [paths] relativePath in
                try paths.resolveRecording(relativePath: relativePath)
            }
        )
        shortcut = CarbonGlobalShortcut()

        let transport = URLSessionTransport(session: .shared)
        let factory = StoreProviderFactory(
            profiles: profiles,
            dictionary: dictionary,
            transport: transport
        )
        orchestrator = DictationOrchestrator(
            records: records,
            audioFiles: audioFiles,
            audioCapture: capture,
            providerFactory: factory,
            optionsProvider: StorePipelineOptionsProvider(settings: settings),
            clipboard: clipboard,
            injector: injector,
            audioURLResolver: { [paths] relativePath in
                try paths.resolveRecording(relativePath: relativePath)
            }
        )
        statistics = StatisticsService(records: records)
        lifecycle = RecordLifecycleService(records: records, audioFiles: audioFiles)
        export = HistoryExportService(records: records)
        storage = StorageStatisticsService(
            records: records,
            audioFiles: audioFiles,
            databaseSizeBytes: { [database] in
                let attributes = try FileManager.default.attributesOfItem(atPath: database.databasePath)
                return (attributes[.size] as? NSNumber)?.int64Value ?? 0
            }
        )
        recovery = StartupRecoveryService(records: records, audioFiles: audioFiles)

        overlay = RecordingOverlayController { [weak self] in
            Task { await self?.orchestrator.cancelRecording() }
        }
        menuBar = StatusItemMenuBarController(actions: MenuBarActions(
            toggleRecording: { [weak self] in
                Task { @MainActor in self?.toggleRecording() }
            },
            cancelRecording: { [weak self] in
                Task { @MainActor in await self?.orchestrator.cancelRecording() }
            },
            openMainWindow: { [weak self] in
                Task { @MainActor in self?.openMainWindowHandler() }
            },
            openHistory: { [weak self] in
                Task { @MainActor in self?.openHistoryHandler() }
            },
            openSettings: { [weak self] in
                Task { @MainActor in self?.openSettingsHandler() }
            },
            quit: {
                Task { @MainActor in NSApp.terminate(nil) }
            }
        ))
    }

    /// 启动：单实例检查之后调用。执行恢复扫描并接线快捷键。
    func start() async {
        _ = try? await recovery.recoverOnLaunch()
        await wireShortcut()
        observeEvents()
    }

    /// 快捷键按下：有活跃会话则停止，否则开始。
    func toggleRecording() {
        Task {
            let active = await orchestrator.activeRecordID
            if active != nil {
                await orchestrator.stopRecording()
            } else {
                _ = try? await orchestrator.startRecording()
            }
        }
    }

    private var statusEventTask: Task<Void, Never>?
    private var currentLevel: Float = 0
    private var currentStatus: DictationStatus?
    private var sessionStartedAt: Date?

    private func wireShortcut() async {
        // 从设置读取快捷键；未设置用默认 ⌥Space。
        let descriptor = CarbonGlobalShortcut.default
        try? await shortcut.register(descriptor)
        shortcutEventTask?.cancel()
        shortcutEventTask = Task { [weak self] in
            guard let events = self?.shortcut.events else { return }
            for await _ in events {
                self?.toggleRecording()
            }
        }
    }

    /// 事件接线：采集电平 → 悬浮条；会话状态 → 菜单栏与悬浮条。
    private func observeEvents() {
        levelEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in capture.events {
                if case .levelUpdated(let level) = event {
                    currentLevel = level
                    refreshOverlay()
                }
            }
        }
        statusEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in orchestrator.events {
                switch event {
                case .statusChanged(_, let status):
                    currentStatus = status
                    if status == .recording, sessionStartedAt == nil {
                        sessionStartedAt = Date()
                    }
                    await menuBar.update(MenuBarState(
                        status: status,
                        hasActiveSession: !status.isSettled
                    ))
                    refreshOverlay()
                case .sessionFinished:
                    currentStatus = nil
                    currentLevel = 0
                    sessionStartedAt = nil
                    await menuBar.update(.idle)
                    overlay.hide()
                case .levelUpdated:
                    break
                }
            }
        }
    }

    private func refreshOverlay() {
        guard let status = currentStatus, !status.isSettled else { return }
        let elapsed = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        overlay.show(state: RecordingOverlayState(
            status: status,
            level: currentLevel,
            elapsedSeconds: elapsed
        ))
    }
}
