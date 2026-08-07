import AppKit
import OpenTypelessPlatform
import SwiftUI

/// OpenTypeless 应用入口（FND-001 的 Xcode 工程以本类型为 @main）。
///
/// 启动顺序：单实例守卫 → 组合根 → 启动恢复 → 快捷键/事件接线。
/// 主窗口约 1100×720、最小 860×560（DESIGN.md §4）；设置使用原生
/// Settings 场景。
@main
struct OpenTypelessApp: App {
    @StateObject private var compositionHolder = CompositionHolder()
    @Environment(\.openWindow) private var openWindow

    init() {
        // 单实例守卫必须最早执行：双开激活旧实例并退出。
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.opentypeless.app"
        if !SingleInstanceGuard.ensureSingleInstance(bundleIdentifier: bundleID) {
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup("OpenTypeless", id: "main") {
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
            .frame(idealWidth: 1_100, idealHeight: 720)
            .task {
                compositionHolder.start(bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.opentypeless.app")
                compositionHolder.composition?.openMainWindowHandler = {
                    Task { @MainActor in
                        NSApp.activate()
                    }
                }
            }
        }
        .defaultSize(width: 1_100, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup("设置", id: "settings") {
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

    func start(bundleIdentifier: String) {
        guard composition == nil, startupError == nil else { return }
        do {
            let composition = try AppComposition(bundleIdentifier: bundleIdentifier)
            self.composition = composition
            Task {
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
        VStack(spacing: DS.Spacing.lg) {
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
        .padding(DS.Spacing.xxxl)
    }
}
