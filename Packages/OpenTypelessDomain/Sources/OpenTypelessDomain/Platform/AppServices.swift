import Foundation

/// 登录自动启动能力协议（macOS 实现基于 SMAppService）。
public protocol AutostartService: Sendable {
    /// 当前是否已注册登录启动。
    func isEnabled() async -> Bool

    /// 注册或取消登录启动。
    func setEnabled(_ enabled: Bool) async throws
}

/// 菜单栏展示状态（平台无关快照）。
public struct MenuBarState: Sendable, Equatable {
    /// 当前口述状态；nil 表示空闲。
    public var status: DictationStatus?
    /// 是否有录音会话进行中（用于菜单项文案切换）。
    public var hasActiveSession: Bool

    public init(status: DictationStatus?, hasActiveSession: Bool) {
        self.status = status
        self.hasActiveSession = hasActiveSession
    }

    public static let idle = MenuBarState(status: nil, hasActiveSession: false)
}

/// 菜单栏能力协议。
///
/// macOS 实现基于 MenuBarExtra / NSStatusItem；菜单动作（开始/停止、
/// 打开主窗口、打开历史、设置、退出）由应用层注入，本协议只同步展示状态。
public protocol MenuBarService: Sendable {
    /// 更新菜单栏图标与状态文案。
    func update(_ state: MenuBarState) async
}
