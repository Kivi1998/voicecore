import Foundation

/// 音频输入设备描述（平台无关）。
public struct AudioInputDevice: Identifiable, Codable, Sendable, Equatable {
    /// 平台提供的稳定设备标识。
    public var id: String
    public var name: String
    public var isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

/// 录音采集过程中的异步事件。
public enum AudioCaptureEvent: Sendable, Equatable {
    /// 输入电平（0～1），仅供录音胶囊展示。
    case levelUpdated(Float)
    /// 输入设备在采集中断开；已采集内容必须已安全落盘。
    case deviceDisconnected
    /// 采集或写盘失败；已落盘内容不得被删除或覆盖。
    case failed(DictationError)
}

/// 录音正常结束后的结果。
public struct AudioCaptureResult: Sendable, Equatable {
    /// 相对录音根目录路径。
    public var relativePath: String
    public var mimeType: String
    public var durationMs: Int64
    public var sizeBytes: Int64

    public init(relativePath: String, mimeType: String, durationMs: Int64, sizeBytes: Int64) {
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
    }
}

/// 录音能力协议。
///
/// macOS 实现位于 VoiceCorePlatform（AVFoundation）；测试替身与未来
/// iOS 实现实现同一协议。实现必须满足：
/// - 音频边采集边写入持久文件，严禁先只保存在内存再在结束时保存；
/// - `AVAudioPCMBuffer`、设备对象与 AVFoundation 错误类型不得泄漏到本接口；
/// - 设备断开、权限撤销、写盘失败时，已采集内容安全关闭并可诊断。
public protocol AudioCapture: Sendable {
    /// 采集事件流；在开始采集前取得，随会话结束而结束。
    var events: AsyncStream<AudioCaptureEvent> { get }

    /// 枚举可用输入设备。
    func listInputDevices() async throws -> [AudioInputDevice]

    /// 开始采集并持续写盘到指定相对路径对应的文件。
    /// - Parameters:
    ///   - deviceID: 目标设备标识；nil 表示系统默认设备。
    ///   - relativePath: 相对录音根目录的目标路径（已由上层校验）。
    func start(deviceID: String?, writingTo relativePath: String) async throws

    /// 正常停止：安全关闭并校验文件后返回结果。
    func stop() async throws -> AudioCaptureResult

    /// 用户取消：安全关闭文件；已落盘内容是否保留由上层决定，本接口不删除文件。
    func cancel() async
}
