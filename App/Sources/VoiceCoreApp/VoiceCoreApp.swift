import AppKit
import SwiftUI
import VoiceCorePlatform

/// VoiceCore 应用入口（FND-001 的 Xcode 工程以本类型为 @main）。
///
/// 启动顺序：单实例守卫 → 组合根 → 启动恢复 → 快捷键/事件接线。
/// 主窗口约 1100×720、最小 860×560（DESIGN.md §4）；设置使用原生
/// Settings 场景。
@main
struct VoiceCoreApp: App {
    @StateObject private var compositionHolder = CompositionHolder()
    @Environment(\.openWindow) private var openWindow

    init() {
        // 单实例守卫必须最早执行：双开激活旧实例并退出。UI 测试使用隔离数据目录，
        // 且可能连续拉起多个进程，因此只在显式测试模式下跳过守卫。
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.voicecore.app"
        if UITestLaunchConfiguration.current == nil,
           !SingleInstanceGuard.ensureSingleInstance(bundleIdentifier: bundleID) {
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup("VoiceCore", id: "main") {
            Group {
                if let composition = compositionHolder.composition {
                    RootView(composition: composition)
                        .frame(minWidth: 860, minHeight: 560)
                } else if let error = compositionHolder.startupError {
                    StartupErrorView(message: error)
                        .frame(minWidth: 480, minHeight: 320)
                } else {
                    ProgressView("正在启动…")
                        .frame(minWidth: 480, minHeight: 320)
                }
            }
            .frame(idealWidth: 1100, idealHeight: 720)
            .task {
                await compositionHolder.start(
                    bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.voicecore.app"
                )
                compositionHolder.composition?.openMainWindowHandler = {
                    Task { @MainActor in
                        NSApp.activate()
                        openWindow(id: "main")
                    }
                }
                compositionHolder.composition?.openHistoryHandler = {
                    Task { @MainActor in
                        NSApp.activate()
                        openWindow(id: "main")
                        compositionHolder.composition?.requestedPage = .history
                    }
                }
                compositionHolder.composition?.openSettingsHandler = {
                    Task { @MainActor in
                        NSApp.activate()
                        openWindow(id: "settings")
                    }
                }
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("\(L10n.Page.settings)…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup(L10n.Page.settings, id: "settings") {
            Group {
                if let composition = compositionHolder.composition {
                    SettingsView(composition: composition)
                }
            }
            .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 680, height: 540)
        .windowResizability(.contentSize)
    }
}

/// 组合根惰性构造（启动失败展示错误而不是崩溃）。
@MainActor
final class CompositionHolder: ObservableObject {
    @Published var composition: AppComposition?
    @Published var startupError: String?

    func start(bundleIdentifier: String) async {
        guard composition == nil, startupError == nil else { return }
        let testConfiguration = UITestLaunchConfiguration.current
        if testConfiguration?.scenario == .startupError {
            startupError = "界面测试模拟的数据初始化失败。"
            return
        }
        do {
            let dataBundleIdentifier = testConfiguration?.dataBundleIdentifier(base: bundleIdentifier)
                ?? bundleIdentifier
            let composition = try AppComposition(bundleIdentifier: dataBundleIdentifier)
            if let testConfiguration {
                try await composition.prepareForUITest(testConfiguration.scenario)
            }
            self.composition = composition
            if testConfiguration == nil {
                await composition.start()
            }
        } catch {
            startupError = "应用数据初始化失败，请检查磁盘权限后重试。"
        }
    }
}

/// 启动失败占位（不伪造可用界面）。
struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("无法启动")
                .font(.title2)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.xxxl)
        .accessibilityIdentifier("startup.error")
    }
}
