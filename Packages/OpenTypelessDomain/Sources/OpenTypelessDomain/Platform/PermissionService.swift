import Foundation

/// 权限种类。
public enum PermissionKind: String, Codable, Sendable, CaseIterable {
    /// 麦克风。
    case microphone
    /// 辅助功能（用于向其他应用写入文字）。
    case accessibility
}

/// 权限状态。
public enum PermissionState: String, Codable, Sendable, CaseIterable {
    /// 尚未向用户请求。
    case notDetermined
    case granted
    case denied
    /// 受系统限制（例如家长控制），用户无法直接授权。
    case restricted
}

/// 权限能力协议。
///
/// 权限提示必须由用户操作触发；实现不得静默请求或轮询骚扰用户。
/// 未获得辅助功能权限时，录音、转录、复制和历史功能必须保持可用。
public protocol PermissionService: Sendable {
    /// 查询某类权限当前状态。
    func state(of kind: PermissionKind) async -> PermissionState

    /// 由用户操作触发的授权请求或系统设置跳转，返回操作后的最新状态。
    func request(_ kind: PermissionKind) async -> PermissionState
}
