import AppKit
import ApplicationServices
import Foundation
import OpenTypelessDomain

/// 辅助功能自动输入实现（PLAT-004）。
///
/// 流程（剪贴板中转方案，兼容绝大多数输入框）：
/// 1. 校验辅助功能权限（未授权 → `injectionPermissionDenied`）；
/// 2. 校验存在可输入焦点（无焦点 → `injectionTargetUnavailable`）；
/// 3. 将最终文字写入剪贴板（原剪贴板的保存/恢复由编排器负责）；
/// 4. 经 `CGEvent` 向当前前台应用模拟 ⌘V。
///
/// 模拟按键事件只包含按键码，不包含文字内容；文字不写入日志。
public final class AccessibilityTextInjector: TextInjector, @unchecked Sendable {
    /// 键盘 V 键虚拟键码。
    private static let vKeyCode: CGKeyCode = 0x09

    private let clipboard: any ClipboardService

    public init(clipboard: any ClipboardService) {
        self.clipboard = clipboard
    }

    public func insert(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw DictationError(
                category: .injectionPermissionDenied,
                userMessage: "未获得辅助功能权限，请在系统设置中允许后重试；文字已保存，可直接复制",
                isRetryable: false
            )
        }
        guard Self.hasFocusedElement() else {
            throw DictationError(
                category: .injectionTargetUnavailable,
                userMessage: "当前没有可输入的焦点，请点击输入框后重试；文字已保存，可直接复制",
                isRetryable: false
            )
        }

        await clipboard.writeText(text)
        // 等待剪贴板写入生效再模拟粘贴。
        try await Task.sleep(nanoseconds: 50_000_000)
        try Self.postCommandV()
    }

    // MARK: - 私有

    /// 系统范围内是否存在焦点 UI 元素。
    static func hasFocusedElement() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, let element = focused else { return false }
        // 焦点元素可设置文本（或可接收粘贴）才可输入。
        // 注：Swift 对 CoreFoundation 类型的条件转换恒为真（编译器强制），
        // 此处 `as!` 是 AXUIElement 取值的惯用写法，不存在类型不确定性。
        var settable = DarwinBoolean(false)
        let setResult = AXUIElementIsAttributeSettable(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            &settable
        )
        // 查询失败时保守放行：粘贴方案对多数元素仍有效。
        return setResult != .success || settable.boolValue
    }

    /// 模拟 ⌘V 粘贴。
    static func postCommandV() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DictationError(
                category: .injectionTargetUnavailable,
                userMessage: "无法创建输入事件源",
                isRetryable: true
            )
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw DictationError(
                category: .injectionTargetUnavailable,
                userMessage: "无法创建粘贴按键事件",
                isRetryable: true
            )
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
