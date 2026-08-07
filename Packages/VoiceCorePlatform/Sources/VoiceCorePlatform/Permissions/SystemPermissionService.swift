import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import VoiceCoreDomain

/// macOS 系统权限服务（PLAT-006）。
///
/// - 权限提示只由用户操作触发（`request`），绝不静默请求或轮询骚扰；
/// - 未授权时给出系统设置跳转，录音/转录/复制/历史功能不受影响。
public final class SystemPermissionService: PermissionService, @unchecked Sendable {
    public init() {}

    public func state(of kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .microphone:
            Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        }
    }

    public func request(_ kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .microphone:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                Self.openSystemSettings(pane: "Privacy_Microphone")
            }
            return await state(of: .microphone)
        case .accessibility:
            // 系统弹窗提示一次；仍未授权则跳转系统设置对应面板。
            let trusted = await MainActor.run {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            }
            if !trusted {
                Self.openSystemSettings(pane: "Privacy_Accessibility")
            }
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    // MARK: - 私有

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    private static func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
