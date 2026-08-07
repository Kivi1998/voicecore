import Foundation
import VoiceCoreDomain
import VoiceCorePlatform

extension AppComposition {
    /// 设置页展示的当前快捷键；录制期间仍返回录制前的组合。
    func configuredShortcut() async -> ShortcutDescriptor {
        if let registered = shortcut.registered {
            return registered
        }
        if let shortcutBeforeRecording {
            return shortcutBeforeRecording
        }
        return await storedShortcut()
    }

    /// 进入录制状态时临时注销旧组合，避免按键被全局处理器同时解释为录音开关。
    func beginShortcutRecording() async {
        guard shortcutBeforeRecording == nil else { return }
        if let registered = shortcut.registered {
            shortcutBeforeRecording = registered
        } else {
            shortcutBeforeRecording = await storedShortcut()
        }
        await shortcut.unregister()
    }

    /// 用户取消录制时恢复原组合。
    func cancelShortcutRecording() async {
        guard let previous = shortcutBeforeRecording else { return }
        shortcutBeforeRecording = nil
        try? await shortcut.register(previous)
    }

    /// 注册、持久化新的全局快捷键；任一步失败都会恢复旧组合。
    func updateShortcut(_ descriptor: ShortcutDescriptor) async throws {
        let previous: ShortcutDescriptor = if let shortcutBeforeRecording {
            shortcutBeforeRecording
        } else if let registered = shortcut.registered {
            registered
        } else {
            await storedShortcut()
        }
        shortcutBeforeRecording = nil
        do {
            try await shortcut.register(descriptor)
            let data = try JSONEncoder().encode(descriptor)
            guard let valueJSON = String(data: data, encoding: .utf8) else {
                throw DictationError(
                    category: .unknown,
                    userMessage: "快捷键保存失败，请重试",
                    isRetryable: true
                )
            }
            try await settings.setValue(valueJSON, forKey: .shortcut)
        } catch {
            try? await shortcut.register(previous)
            throw error
        }
    }

    func storedShortcut() async -> ShortcutDescriptor {
        guard let valueJSON = try? await settings.value(forKey: .shortcut),
              let data = valueJSON.data(using: .utf8),
              let descriptor = try? JSONDecoder().decode(ShortcutDescriptor.self, from: data)
        else {
            return CarbonGlobalShortcut.default
        }
        return descriptor
    }
}
