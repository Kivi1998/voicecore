import AppKit
import Foundation
import OpenTypelessDomain
import SwiftUI

/// 录音悬浮条展示状态（平台层视图模型，应用层推送）。
public struct RecordingOverlayState: Sendable, Equatable {
    public var status: DictationStatus
    /// 输入电平（0～1）。
    public var level: Float
    /// 已录音秒数。
    public var elapsedSeconds: TimeInterval

    public init(status: DictationStatus, level: Float = 0, elapsedSeconds: TimeInterval = 0) {
        self.status = status
        self.level = level
        self.elapsedSeconds = elapsedSeconds
    }
}

/// 录音悬浮条 SwiftUI 内容（系统材质，VoiceOver 可读）。
struct RecordingCapsuleView: View {
    let state: RecordingOverlayState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(StatusItemMenuBarController.statusText(for: state.status))
                .font(.callout.weight(.medium))

            // 电平条（同时以文字暴露给 VoiceOver，不仅靠图形表达）。
            Capsule()
                .fill(.secondary.opacity(0.25))
                .frame(width: 48, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.green)
                        .frame(width: 48 * CGFloat(min(1, max(0, state.level))), height: 6)
                }
                .accessibilityLabel("输入电平")
                .accessibilityValue("\(Int(state.level * 100))%")

            Text(Self.formatElapsed(state.elapsedSeconds))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消录音")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // 系统玻璃与材质降级（UI-006）：macOS 26 原生 Liquid Glass，
        // 旧系统系统材质，减少透明度时不透明底；绝不自制“假玻璃”。
        .background(CapsuleGlassBackground())
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 胶囊系统玻璃背景（UI-006）：macOS 26 原生 Liquid Glass，
/// 旧系统降级系统材质，「减少透明度」时不透明保证可读。
private struct CapsuleGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Capsule().fill(.background)
                .shadow(radius: 2, y: 1)
        } else if #available(macOS 26.0, *) {
            Capsule().fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
        }
    }
}

/// 无焦点录音悬浮条控制器（PLAT-005）。
///
/// - `NSPanel` `.nonactivatingPanel`：展示与点击取消均不抢焦点，
///   用户可继续在当前应用操作；
/// - 悬浮于所有空间（`.statusBar` 层级），主窗口关闭后照常工作；
/// - 内容经 `NSHostingView` 桥接 SwiftUI。
@MainActor
public final class RecordingOverlayController {
    private var panel: NSPanel?
    private let onCancel: () -> Void

    /// 创建悬浮条控制器；`onCancel` 在用户点击取消按钮时回调。
    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    /// 展示或更新悬浮条。
    public func show(state: RecordingOverlayState) {
        let panel = ensurePanel()
        let view = RecordingCapsuleView(state: state, onCancel: onCancel)
        panel.contentView = NSHostingView(rootView: view)
        panel.contentView?.setAccessibilityRole(.group)
        panel.contentView?.setAccessibilityLabel(
            "录音状态，\(StatusItemMenuBarController.statusText(for: state.status))"
        )
        positionPanel(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// 隐藏悬浮条。
    public func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - 私有

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    /// 居中置于主屏顶部安全区下方。
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
    }
}
