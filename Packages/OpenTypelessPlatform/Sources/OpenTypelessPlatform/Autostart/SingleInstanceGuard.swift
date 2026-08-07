import AppKit
import Foundation

/// 单实例守卫（PLAT-006）。
///
/// 应用入口在启动最早期调用 `activateOrTerminate`：已存在同 Bundle ID 的
/// 运行实例时激活它并退出当前进程，避免双开导致的全局快捷键冲突与
/// 数据库并发写入。
public enum SingleInstanceGuard {
    /// 若已有其他实例运行：激活之并返回 false（调用方应立即退出进程）。
    /// 当前进程是唯一实例时返回 true 继续启动。
    @MainActor
    public static func ensureSingleInstance(bundleIdentifier: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let others = running.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return true }
        existing.activate()
        return false
    }
}
