import AppKit
import Foundation
import OpenTypelessDomain

/// 菜单栏动作集合（应用层注入；本控制器只做展示与转发）。
public struct MenuBarActions: Sendable {
    /// 开始或停止录音（菜单项文案随状态切换）。
    public var toggleRecording: @Sendable () -> Void
    /// 取消当前录音。
    public var cancelRecording: @Sendable () -> Void
    public var openMainWindow: @Sendable () -> Void
    public var openHistory: @Sendable () -> Void
    public var openSettings: @Sendable () -> Void
    public var quit: @Sendable () -> Void

    public init(
        toggleRecording: @escaping @Sendable () -> Void,
        cancelRecording: @escaping @Sendable () -> Void,
        openMainWindow: @escaping @Sendable () -> Void,
        openHistory: @escaping @Sendable () -> Void,
        openSettings: @escaping @Sendable () -> Void,
        quit: @escaping @Sendable () -> Void
    ) {
        self.toggleRecording = toggleRecording
        self.cancelRecording = cancelRecording
        self.openMainWindow = openMainWindow
        self.openHistory = openHistory
        self.openSettings = openSettings
        self.quit = quit
    }
}

/// NSStatusItem 菜单栏实现（PLAT-005）。
///
/// - 主窗口关闭后依然工作（状态栏常驻，不依赖窗口生命周期）；
/// - 图标与菜单项文案随口述状态更新；VoiceOver 可读
///   （`accessibilityLabel` 同步状态文案）；
/// - 动作全部转发给应用层注入的闭包，本类不含业务逻辑。
@MainActor
public final class StatusItemMenuBarController: NSObject, MenuBarService {
    private let statusItem: NSStatusItem
    private let actions: MenuBarActions
    private var state: MenuBarState = .idle
    private var toggleItem: NSMenuItem?
    private var cancelItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?

    public init(actions: MenuBarActions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        rebuildMenu()
    }

    nonisolated public func update(_ state: MenuBarState) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.state = state
            self.applyState()
        }
    }

    // MARK: - 私有

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: "OpenTypeless"
        )
        button.image?.isTemplate = true
        button.setAccessibilityLabel("OpenTypeless 语音输入，空闲")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "空闲", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        statusMenuItem = statusItem
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "开始录音",
            action: #selector(handleToggle),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle

        let cancel = NSMenuItem(
            title: "取消录音",
            action: #selector(handleCancel),
            keyEquivalent: ""
        )
        cancel.target = self
        menu.addItem(cancel)
        cancelItem = cancel

        menu.addItem(.separator())
        addItem(to: menu, title: "打开主窗口", action: #selector(handleOpenMainWindow))
        addItem(to: menu, title: "历史记录", action: #selector(handleOpenHistory))
        addItem(to: menu, title: "设置…", action: #selector(handleOpenSettings))
        menu.addItem(.separator())
        addItem(to: menu, title: "退出 OpenTypeless", action: #selector(handleQuit))

        self.statusItem.menu = menu
        applyState()
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func applyState() {
        let statusText = Self.statusText(for: state.status)
        statusMenuItem?.title = statusText
        toggleItem?.title = state.hasActiveSession ? "停止录音" : "开始录音"
        cancelItem?.isEnabled = state.hasActiveSession
        statusItem.button?.setAccessibilityLabel("OpenTypeless 语音输入，\(statusText)")

        let symbol = state.hasActiveSession ? "waveform.circle.fill" : "waveform.circle"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "OpenTypeless"
        )
        statusItem.button?.image?.isTemplate = true
    }

    /// 面向用户与 VoiceOver 的状态文案。
    static func statusText(for status: DictationStatus?) -> String {
        guard let status else { return "空闲" }
        switch status {
        case .created, .queued: return "准备中"
        case .recording: return "录音中"
        case .audioSaved: return "录音已保存"
        case .transcribing: return "识别中"
        case .transcribed: return "识别完成"
        case .rewriting: return "改写中"
        case .ready: return "待输入"
        case .injecting: return "正在输入"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        case .recordingFailed: return "录音失败"
        case .transcriptionFailed: return "识别失败"
        case .rewriteFailed: return "改写失败"
        case .injectionFailed: return "输入失败"
        }
    }

    @objc private func handleToggle() { actions.toggleRecording() }
    @objc private func handleCancel() { actions.cancelRecording() }
    @objc private func handleOpenMainWindow() { actions.openMainWindow() }
    @objc private func handleOpenHistory() { actions.openHistory() }
    @objc private func handleOpenSettings() { actions.openSettings() }
    @objc private func handleQuit() { actions.quit() }
}
