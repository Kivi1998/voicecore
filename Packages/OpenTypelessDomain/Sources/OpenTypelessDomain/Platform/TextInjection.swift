import Foundation

/// 向当前输入目标写入文字的能力协议。
///
/// 领域层只调用 `insert(_:)`；macOS 实现负责辅助功能权限检查、
/// 剪贴板中转与模拟粘贴。写入失败是独立错误，不回滚转录结果。
public protocol TextInjector: Sendable {
    /// 将最终文字写入当前焦点输入框。
    /// - Throws: `DictationError`，类别为 `injection_permission_denied`
    ///   或 `injection_target_unavailable` 等。
    func insert(_ text: String) async throws
}

/// 剪贴板内容的可恢复快照。
///
/// 快照可能包含多种数据类型；仅供保存/恢复使用，
/// 不得写入日志、数据库或网络请求。
public struct ClipboardSnapshot: Sendable, Equatable {
    /// 单个剪贴板条目：类型标识与原始数据。
    public struct Item: Sendable, Equatable {
        public var typeIdentifier: String
        public var data: Data

        public init(typeIdentifier: String, data: Data) {
            self.typeIdentifier = typeIdentifier
            self.data = data
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// 空快照（原剪贴板为空）。
    public static let empty = ClipboardSnapshot(items: [])
}

/// 剪贴板能力协议。
///
/// 自动输入流程必须尽可能保存并恢复用户原剪贴板内容；
/// 恢复失败时抛出可诊断错误，错误信息不得包含剪贴板完整内容。
public protocol ClipboardService: Sendable {
    /// 保存当前剪贴板内容。
    func save() async -> ClipboardSnapshot

    /// 写入文本到剪贴板。
    func writeText(_ text: String) async

    /// 读取当前剪贴板纯文本（用于诊断与复制操作）。
    func readText() async -> String?

    /// 恢复此前保存的剪贴板内容。
    func restore(_ snapshot: ClipboardSnapshot) async throws
}
