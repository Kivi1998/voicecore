import Foundation
import ServiceManagement
import VoiceCoreDomain

/// SMAppService 登录自动启动实现（PLAT-006，macOS 13+）。
public final class SMAppLoginItemService: AutostartService, @unchecked Sendable {
    public init() {}

    public func isEnabled() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) async throws {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notFound {
                    try await SMAppService.mainApp.unregister()
                }
            }
        } catch {
            throw DictationError(
                category: .unknown,
                userMessage: enabled ? "开机启动注册失败，请稍后在系统设置中检查" : "取消开机启动失败"
            )
        }
    }
}
