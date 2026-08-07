import Carbon.HIToolbox
import Foundation
import OpenTypelessDomain

/// Carbon RegisterEventHotKey 全局快捷键实现（PLAT-002）。
///
/// 选择 Carbon 热键而非 `NSEvent` 全局监听的原因：
/// - 不需要辅助功能/输入监听权限即可在其他应用前台时接收按键；
/// - 注册成功即独占该组合键，系统级冲突在注册时即可发现；
/// - 「按一次开始、再按一次停止」由编排器解释，本类只上报每次按下。
///
/// 事件处理在运行循环线程执行，只向异步流投递，不做任何业务操作。
public final class CarbonGlobalShortcut: GlobalShortcut, @unchecked Sendable {
    /// 默认快捷键：⌥Space（macOS 14 无系统占用；注册失败会报冲突，由用户改绑）。
    public static let `default` = ShortcutDescriptor(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayString: "⌥Space"
    )

    private let lock = NSLock()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var current: ShortcutDescriptor?

    public nonisolated let events: AsyncStream<Void>
    private let eventContinuation: AsyncStream<Void>.Continuation

    /// 热键签名（自增避免与其他使用方冲突）。
    private static let hotKeySignature = OSType(0x4F54_4C53) // 'OTLS'
    private static let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)

    public init() {
        var continuation: AsyncStream<Void>.Continuation!
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - GlobalShortcut

    public func register(_ shortcut: ShortcutDescriptor) async throws {
        await unregister()

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

        lock.withLock {
            self.hotKeyRef = hotKeyRef
            self.eventHandlerRef = handlerRef
            self.current = shortcut
        }
    }

    public func unregister() async {
        let (hotKey, handler): (EventHotKeyRef?, EventHandlerRef?) = lock.withLock {
            let values = (hotKeyRef, eventHandlerRef)
            hotKeyRef = nil
            eventHandlerRef = nil
            current = nil
            return values
        }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    /// 冲突检测：尝试注册后立即注销。Carbon 对进程内重复注册返回
    /// `eventHotKeyExistsErr`；系统范围内其他应用的 Carbon 热键同样可发现。
    /// 注意：无法检测所有非 Carbon 机制的占用（如输入法），结果仅供参考，
    /// 最终权威是 `register` 的成功与否。
    public func conflicts(with shortcut: ShortcutDescriptor) async -> Bool {
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
}
