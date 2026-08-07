import AppKit
import Carbon.HIToolbox
import SwiftUI
import VoiceCoreDomain

/// 把 macOS 键盘事件转换为可持久化的 Carbon 全局快捷键描述。
enum ShortcutDescriptorBuilder {
    private static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func make(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> ShortcutDescriptor? {
        let normalizedModifiers = modifiers.intersection(allowedModifiers)
        if keyCode == UInt16(kVK_Function), normalizedModifiers.isEmpty {
            return ShortcutDescriptor(
                keyCode: UInt32(kVK_Function),
                modifiers: 0,
                displayString: "Fn"
            )
        }
        guard !normalizedModifiers.isEmpty,
              let keyName = keyName(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers)
        else {
            return nil
        }

        return ShortcutDescriptor(
            keyCode: UInt32(keyCode),
            modifiers: carbonModifiers(normalizedModifiers),
            displayString: displayModifiers(normalizedModifiers) + keyName
        )
    }

    private static func carbonModifiers(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) {
            result |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            result |= UInt32(optionKey)
        }
        if modifiers.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if modifiers.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }

    private static func displayModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }
        if modifiers.contains(.command) {
            result += "⌘"
        }
        return result
    }

    private static func keyName(keyCode: UInt16, charactersIgnoringModifiers: String?) -> String? {
        if let special = specialKeyName(keyCode) {
            return special
        }
        guard !ignoredKeyCodes.contains(keyCode),
              let charactersIgnoringModifiers,
              let character = charactersIgnoringModifiers.first,
              !character.isWhitespace,
              !character.isNewline
        else {
            return nil
        }
        return String(character).uppercased()
    }

    private static func specialKeyName(_ keyCode: UInt16) -> String? {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓", UInt16(kVK_Home): "↖",
            UInt16(kVK_End): "↘", UInt16(kVK_PageUp): "⇞",
            UInt16(kVK_PageDown): "⇟", UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12", UInt16(kVK_F13): "F13",
            UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17",
            UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19",
            UInt16(kVK_F20): "F20"
        ]
        return specialKeys[keyCode]
    }

    /// Escape 用于取消录制；纯修饰键不产生可绑定的快捷键。
    private static let ignoredKeyCodes = Set<UInt16>([
        UInt16(kVK_Escape), UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Shift), UInt16(kVK_RightShift), UInt16(kVK_Option),
        UInt16(kVK_RightOption), UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock), UInt16(kVK_Function)
    ])
}

/// 原生 macOS 快捷键录制按钮：点击后按下新组合，Escape 取消。
struct ShortcutRecorderControl: NSViewRepresentable {
    let shortcut: ShortcutDescriptor
    let onBeginRecording: () -> Void
    let onCancelRecording: () -> Void
    let onCommit: (ShortcutDescriptor) -> Void

    func makeNSView(context _: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        configure(button)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context _: Context) {
        configure(button)
    }

    private func configure(_ button: ShortcutRecorderButton) {
        button.update(
            shortcut: shortcut,
            onBeginRecording: onBeginRecording,
            onCancelRecording: onCancelRecording,
            onCommit: onCommit
        )
    }
}

final class ShortcutRecorderButton: NSButton {
    private var shortcut = ShortcutDescriptor(keyCode: 0, modifiers: 0, displayString: "")
    private var isRecording = false
    private var onBeginRecording: () -> Void = {}
    private var onCancelRecording: () -> Void = {}
    private var onCommit: (ShortcutDescriptor) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        focusRingType = .exterior
        toolTip = "点击后按下新的快捷键组合；按 Escape 取消"
        setAccessibilityLabel("全局快捷键")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func update(
        shortcut: ShortcutDescriptor,
        onBeginRecording: @escaping () -> Void,
        onCancelRecording: @escaping () -> Void,
        onCommit: @escaping (ShortcutDescriptor) -> Void
    ) {
        self.shortcut = shortcut
        self.onBeginRecording = onBeginRecording
        self.onCancelRecording = onCancelRecording
        self.onCommit = onCommit
        if !isRecording {
            title = shortcut.displayString
            setAccessibilityValue(shortcut.displayString)
        }
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "请按下新快捷键…"
        setAccessibilityValue("正在录制快捷键")
        onBeginRecording()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        guard let candidate = ShortcutDescriptorBuilder.make(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) else {
            NSSound.beep()
            title = "请同时按修饰键"
            return
        }

        isRecording = false
        title = candidate.displayString
        setAccessibilityValue(candidate.displayString)
        onCommit(candidate)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording,
              event.keyCode == UInt16(kVK_Function),
              event.modifierFlags.contains(.function),
              let candidate = ShortcutDescriptorBuilder.make(
                  keyCode: event.keyCode,
                  modifiers: event.modifierFlags,
                  charactersIgnoringModifiers: event.charactersIgnoringModifiers
              )
        else {
            super.flagsChanged(with: event)
            return
        }

        isRecording = false
        title = candidate.displayString
        setAccessibilityValue(candidate.displayString)
        onCommit(candidate)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording(makeFirstResponderNil: false)
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording(makeFirstResponderNil: Bool = true) {
        guard isRecording else { return }
        isRecording = false
        title = shortcut.displayString
        setAccessibilityValue(shortcut.displayString)
        onCancelRecording()
        if makeFirstResponderNil {
            window?.makeFirstResponder(nil)
        }
    }
}
