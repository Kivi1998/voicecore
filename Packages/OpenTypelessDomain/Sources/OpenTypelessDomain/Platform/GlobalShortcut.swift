import Foundation

/// 平台无关的全局快捷键描述。
///
/// `keyCode` 与 `modifiers` 为平台键盘事件位掩码值，由平台实现负责
/// 生成、解析和展示；领域层只把它当作可持久化的值对象。
public struct ShortcutDescriptor: Codable, Sendable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// 面向用户的展示文本，例如 `⌥Space`，由平台实现生成。
    public var displayString: String

    public init(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }
}

/// 全局快捷键能力协议。
///
/// “按一次开始、再按一次结束”的语义由口述编排器解释；
/// 本接口只负责注册、注销并上报每一次按下事件。
public protocol GlobalShortcut: Sendable {
    /// 快捷键按下事件流；后台与其他应用前台时也必须可达。
    var events: AsyncStream<Void> { get }

    /// 注册全局快捷键；重复注册视为重绑。
    func register(_ shortcut: ShortcutDescriptor) async throws

    /// 注销当前快捷键。
    func unregister() async

    /// 检测候选快捷键与系统或本机常见占用的冲突。
    func conflicts(with shortcut: ShortcutDescriptor) async -> Bool
}
