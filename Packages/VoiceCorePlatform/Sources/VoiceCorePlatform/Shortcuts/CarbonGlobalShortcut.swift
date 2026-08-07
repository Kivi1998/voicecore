import AppKit
import Carbon.HIToolbox
import Foundation
import VoiceCoreDomain

/// Carbon RegisterEventHotKey 全局快捷键实现（PLAT-002）。
///
/// 选择 Carbon 热键而非 `NSEvent` 全局监听的原因：
/// - 不需要辅助功能/输入监听权限即可在其他应用前台时接收按键；
/// - 注册成功即独占该组合键，系统级冲突在注册时即可发现；
/// - 「按一次开始、再按一次停止」由编排器解释，本类只上报每次按下。
///
/// 事件处理在运行循环线程执行，只向异步流投递，不做任何业务操作。
public final class CarbonGlobalShortcut: GlobalShortcut, @unchecked Sendable {
    /// 默认快捷键：单独轻按并松开 Fn。
    public static let `default` = ShortcutDescriptor(
        keyCode: UInt32(kVK_Function),
        modifiers: 0,
        displayString: "Fn"
    )

    /// 未获辅助功能权限时的无权限回退组合键，确保录音入口仍可用。
    public static let permissionFallback = ShortcutDescriptor(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayString: "⌥Space"
    )

    private let lock = NSLock()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var keyboardMonitor: KeyboardEventMonitor?
    private var current: ShortcutDescriptor?

    public nonisolated let events: AsyncStream<Void>
    private let eventContinuation: AsyncStream<Void>.Continuation
    /// 录音期间按下 Escape 的事件流；组合根决定当前是否需要取消。
    public nonisolated let cancelEvents: AsyncStream<Void>
    private let cancelEventContinuation: AsyncStream<Void>.Continuation

    /// 热键签名（自增避免与其他使用方冲突）。
    private static let hotKeySignature = OSType(0x4F54_4C53) // 'OTLS'
    private static let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)

    public init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        events = stream
        eventContinuation = continuation
        let (cancelStream, cancelContinuation) = AsyncStream<Void>.makeStream()
        cancelEvents = cancelStream
        cancelEventContinuation = cancelContinuation
    }

    deinit {
        eventContinuation.finish()
        cancelEventContinuation.finish()
    }

    // MARK: - GlobalShortcut

    public func register(_ shortcut: ShortcutDescriptor) async throws {
        await unregister()

        if Self.isFunctionKey(shortcut) {
            let monitor = try await makeKeyboardMonitor(listensForFunctionKey: true)
            lock.withLock {
                keyboardMonitor = monitor
                current = shortcut
            }
            return
        }

        let handlerRef = try installEventHandler()
        let hotKeyRef = try registerHotKey(shortcut, handlerRef: handlerRef)
        // 普通 Carbon 组合键不依赖辅助功能权限；Escape 监听尽力启用，
        // 权限不足时不影响组合键本身工作。
        let monitor = try? await makeKeyboardMonitor(listensForFunctionKey: false)
        lock.withLock {
            self.hotKeyRef = hotKeyRef
            self.eventHandlerRef = handlerRef
            self.keyboardMonitor = monitor
            self.current = shortcut
        }
    }

    private func makeKeyboardMonitor(listensForFunctionKey: Bool) async throws -> KeyboardEventMonitor {
        try await MainActor.run {
            let monitor = KeyboardEventMonitor(
                listensForFunctionKey: listensForFunctionKey,
                onFunctionKeyTap: { [eventContinuation] in
                    eventContinuation.yield(())
                },
                onEscape: { [cancelEventContinuation] in
                    cancelEventContinuation.yield(())
                }
            )
            try monitor.start()
            return monitor
        }
    }

    /// 安装应用级键盘事件处理器；只向异步流投递按下事件。
    private func installEventHandler() throws -> EventHandlerRef {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<CarbonGlobalShortcut>.fromOpaque(userData)
                .takeUnretainedValue()
            service.eventContinuation.yield(())
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr, let handlerRef else {
            throw DictationError(
                category: .unknown,
                userMessage: "快捷键服务初始化失败",
                isRetryable: true
            )
        }
        return handlerRef
    }

    /// 注册热键；失败时负责回收已安装的事件处理器。
    private func registerHotKey(
        _ shortcut: ShortcutDescriptor,
        handlerRef: EventHandlerRef
    ) throws -> EventHotKeyRef {
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr, let hotKeyRef else {
            RemoveEventHandler(handlerRef)
            if registerStatus == eventHotKeyExistsErr {
                throw DictationError(
                    category: .configurationInvalid,
                    userMessage: "快捷键 \(shortcut.displayString) 已被占用，请更换",
                    isRetryable: false
                )
            }
            throw DictationError(
                category: .unknown,
                userMessage: "快捷键注册失败（\(registerStatus)），请更换按键组合",
                isRetryable: false
            )
        }
        return hotKeyRef
    }

    public func unregister() async {
        let resources = lock.withLock {
            let values = RegistrationResources(
                hotKey: hotKeyRef,
                handler: eventHandlerRef,
                keyboardMonitor: keyboardMonitor
            )
            hotKeyRef = nil
            eventHandlerRef = nil
            keyboardMonitor = nil
            current = nil
            return values
        }
        if let hotKey = resources.hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler = resources.handler {
            RemoveEventHandler(handler)
        }
        if let monitor = resources.keyboardMonitor {
            await MainActor.run {
                monitor.stop()
            }
        }
    }

    /// 冲突检测：尝试注册后立即注销。Carbon 对进程内重复注册返回
    /// `eventHotKeyExistsErr`；系统范围内其他应用的 Carbon 热键同样可发现。
    /// 注意：无法检测所有非 Carbon 机制的占用（如输入法），结果仅供参考，
    /// 最终权威是 `register` 的成功与否。
    public func conflicts(with shortcut: ShortcutDescriptor) async -> Bool {
        if Self.isFunctionKey(shortcut) {
            return false
        }
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.hotKeySignature, id: 2),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            return false
        }
        return status != noErr
    }

    /// 当前已注册的快捷键（诊断与设置页展示）。
    public var registered: ShortcutDescriptor? {
        lock.withLock { current }
    }

    private static func isFunctionKey(_ shortcut: ShortcutDescriptor) -> Bool {
        shortcut.keyCode == UInt32(kVK_Function) && shortcut.modifiers == 0
    }
}

private struct RegistrationResources {
    let hotKey: EventHotKeyRef?
    let handler: EventHandlerRef?
    let keyboardMonitor: KeyboardEventMonitor?
}

/// Carbon 无法注册“只有修饰键”的快捷键，因此 Fn 与 Escape 使用只读 CGEventTap。
/// Fn 只在按下后没有出现其他按键、并最终松开时触发一次，避免 Fn 组合键误触。
private final class KeyboardEventMonitor: @unchecked Sendable {
    private let listensForFunctionKey: Bool
    private let onFunctionKeyTap: @Sendable () -> Void
    private let onEscape: @Sendable () -> Void
    private let stateLock = NSLock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var functionKeyRecognizer = FunctionKeyTapRecognizer()

    init(
        listensForFunctionKey: Bool,
        onFunctionKeyTap: @escaping @Sendable () -> Void,
        onEscape: @escaping @Sendable () -> Void
    ) {
        self.listensForFunctionKey = listensForFunctionKey
        self.onFunctionKeyTap = onFunctionKeyTap
        self.onEscape = onEscape
    }

    @MainActor
    func start() throws {
        let eventMask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw DictationError(
                category: .injectionPermissionDenied,
                userMessage: "Fn 快捷键与 Escape 取消需要辅助功能权限，请在系统设置中允许 VoiceCore。",
                isRetryable: true
            )
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw DictationError(
                category: .unknown,
                userMessage: "键盘监听初始化失败，请重新启动 VoiceCore。",
                isRetryable: true
            )
        }
        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    @MainActor
    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        stateLock.withLock {
            functionKeyRecognizer.reset()
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<KeyboardEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.handle(
            type: type,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags
        )
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        if type == .keyDown {
            if keyCode == UInt16(kVK_Escape) {
                onEscape()
            }
            stateLock.withLock {
                functionKeyRecognizer.noteCombinationInput()
            }
            return
        }

        guard type == .flagsChanged else { return }
        if keyCode != UInt16(kVK_Function) {
            stateLock.withLock {
                functionKeyRecognizer.noteCombinationInput()
            }
            return
        }

        let isDown = flags.contains(.maskSecondaryFn)
        let recognizedTap = stateLock.withLock {
            functionKeyRecognizer.handleFunctionFlag(isDown: isDown)
        }
        if listensForFunctionKey, recognizedTap {
            onFunctionKeyTap()
        }
    }
}

/// 单独 Fn 轻按识别器。只在完整的“按下→松开”序列中、且期间没有其他
/// 键盘输入时返回一次 `true`，从而避免 Fn 组合键和系统重复事件误触发。
struct FunctionKeyTapRecognizer {
    private(set) var isFunctionKeyDown = false
    private var wasCombined = false

    mutating func handleFunctionFlag(isDown: Bool) -> Bool {
        if isDown {
            if !isFunctionKeyDown {
                isFunctionKeyDown = true
                wasCombined = false
            }
            return false
        }
        guard isFunctionKeyDown else { return false }
        let recognizedTap = !wasCombined
        reset()
        return recognizedTap
    }

    mutating func noteCombinationInput() {
        if isFunctionKeyDown {
            wasCombined = true
        }
    }

    mutating func reset() {
        isFunctionKeyDown = false
        wasCombined = false
    }
}
