import AudioToolbox

// AVFoundation 实时回调与格式转换 API 未标注并发域；缓冲只在回调线程使用。
@preconcurrency import AVFoundation
import Foundation
import OpenTypelessDomain

/// AVFoundation 录音采集实现（PLAT-003）。
///
/// 保证（对应 `AudioCapture` 协议约束）：
/// - 音频经 `AVAudioEngine` 输入回调实时编码为 AAC（m4a）并**边录边写入
///   `.partial` 半成品文件**，绝不只在内存累积；
/// - 半成品路径由组合根注入的解析器给出（`FileAudioFileStore` 的
///   `.partial` 约定），停止后由仓储 `finalize` 校验并改名；
/// - 设备配置变化（拔插默认设备）安全关闭已采集内容并上报
///   `deviceDisconnected`，已落盘内容不删除不覆盖；
/// - 采集回调线程只做格式转换与写盘，不接触数据库与网络；
/// - AVFoundation 类型不泄漏到接口之外。
///
/// 线程模型：公开方法可在任意线程调用，内部以锁串行化会话状态；
/// 电平事件限频（约 10Hz）经异步流上报。
public final class AVAudioCaptureService: AudioCapture, @unchecked Sendable {
    /// 录音半成品绝对路径解析（由组合根以录音根目录实现）。
    public typealias PartialURLResolver = @Sendable (String) throws -> URL

    private let partialURLResolver: PartialURLResolver
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var session: CaptureSession?

    /// 会话内部状态（仅在 lock 内访问；tap 回调在实时线程读写文件句柄）。
    private final class CaptureSession {
        let relativePath: String
        let engine: AVAudioEngine
        let file: AVAudioFile
        let converter: AVAudioConverter
        /// 已写入的输出帧数（用于时长）。
        var framesWritten: Int64 = 0
        let outputSampleRate: Double
        var configChangeObserver: NSObjectProtocol?
        var lastLevelSentAt: Date = .distantPast
        var isStopping = false

        init(
            relativePath: String,
            engine: AVAudioEngine,
            file: AVAudioFile,
            converter: AVAudioConverter
        ) {
            self.relativePath = relativePath
            self.engine = engine
            self.file = file
            self.converter = converter
            outputSampleRate = converter.outputFormat.sampleRate
        }
    }

    public nonisolated let events: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation

    public init(
        partialURLResolver: @escaping PartialURLResolver,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.partialURLResolver = partialURLResolver
        self.now = now
        var continuation: AsyncStream<AudioCaptureEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - 设备枚举

    public func listInputDevices() async throws -> [AudioInputDevice] {
        let defaultID = Self.defaultInputDeviceID()
        return Self.inputAudioDeviceIDs().compactMap { id in
            guard Self.deviceHasInputStreams(id) else { return nil }
            return AudioInputDevice(
                id: String(id),
                name: Self.deviceName(id) ?? "未知设备",
                isSystemDefault: id == defaultID
            )
        }
    }

    // MARK: - 采集控制

    public func start(deviceID: String?, writingTo relativePath: String) async throws {
        // 麦克风权限：未授权直接失败，引导由 PermissionService 负责。
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError(
                category: .permissionDenied,
                userMessage: "未获得麦克风权限，请在系统设置中允许访问麦克风",
                isRetryable: false
            )
        }

        try lock.withLock {
            guard session == nil else {
                throw DictationError(
                    category: .configurationInvalid,
                    userMessage: "已有录音进行中",
                    isRetryable: false
                )
            }
        }

        let engine = AVAudioEngine()
        // 指定输入设备（nil 为系统默认）。
        if let deviceID, let numericID = UInt32(deviceID) {
            try Self.assignInputDevice(AudioDeviceID(numericID), to: engine)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw DictationError(
                category: .deviceUnavailable,
                userMessage: "未检测到可用麦克风，请检查输入设备"
            )
        }

        // 输出：AAC 单声道 m4a；采样率跟随输入，避免重采样失真。
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let partialURL = try partialURLResolver(relativePath + ".partial")
        try FileManager.default.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // 同记录重试或异常残留：删除旧半成品重新开始，正式文件不受影响。
        try? FileManager.default.removeItem(at: partialURL)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: partialURL, settings: outputSettings)
        } catch {
            throw DictationError(
                category: .audioWriteFailed,
                userMessage: "无法创建录音文件，请检查磁盘空间和目录权限"
            )
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
            throw DictationError(
                category: .deviceUnavailable,
                userMessage: "音频格式不受支持，无法开始录音",
                isRetryable: false
            )
        }

        let newSession = CaptureSession(
            relativePath: relativePath,
            engine: engine,
            file: file,
            converter: converter
        )

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        // 设备配置变化（拔插）：安全关闭并上报，已落盘内容保留。
        newSession.configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            if let observer = newSession.configChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            throw DictationError(
                category: .deviceUnavailable,
                userMessage: "麦克风启动失败，请检查输入设备是否被占用"
            )
        }

        lock.withLock { session = newSession }
    }

    public func stop() async throws -> AudioCaptureResult {
        let current: CaptureSession? = lock.withLock {
            let current = session
            session = nil
            current?.isStopping = true
            return current
        }
        guard let current else {
            throw DictationError(
                category: .audioInvalid,
                userMessage: "没有进行中的录音",
                isRetryable: false
            )
        }
        teardown(current)

        let durationMs = Int64(
            Double(current.framesWritten) / max(1, current.outputSampleRate) * 1000
        )
        let partialURL = try partialURLResolver(current.relativePath + ".partial")
        let size = (try? FileManager.default.attributesOfItem(atPath: partialURL.path)[.size])
            .map { ($0 as? NSNumber)?.int64Value ?? 0 } ?? 0
        return AudioCaptureResult(
            relativePath: current.relativePath,
            mimeType: "audio/mp4",
            durationMs: durationMs,
            sizeBytes: size
        )
    }

    public func cancel() async {
        let current: CaptureSession? = lock.withLock {
            let current = session
            session = nil
            current?.isStopping = true
            return current
        }
        if let current {
            teardown(current)
        }
    }

    // MARK: - 私有

    /// 实时回调：格式转换并立即写盘；失败只上报事件，不在回调抛错。
    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        let current: CaptureSession? = lock.withLock { session }
        guard let current, !current.isStopping else { return }

        reportLevelIfDue(buffer: buffer, session: current)

        guard let output = AVAudioPCMBuffer(
            pcmFormat: current.converter.outputFormat,
            frameCapacity: max(buffer.frameCapacity, 1024)
        ) else { return }

        let consumption = ConsumptionFlag()
        var conversionError: NSError?
        let status = current.converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumption.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumption.consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            if output.frameLength > 0 {
                do {
                    try current.file.write(from: output)
                    lock.withLock {
                        current.framesWritten += Int64(output.frameLength)
                    }
                } catch {
                    emit(.failed(DictationError(
                        category: .audioWriteFailed,
                        userMessage: "录音写入失败，请检查磁盘空间"
                    )))
                }
            }
        case .error:
            emit(.failed(DictationError(
                category: .audioInvalid,
                userMessage: "音频编码失败",
                isRetryable: false
            )))
        @unknown default:
            break
        }
    }

    /// 输入电平（RMS→近似分贝归一化），限频约 10Hz。
    private func reportLevelIfDue(buffer: AVAudioPCMBuffer, session: CaptureSession) {
        let current = now()
        guard current.timeIntervalSince(session.lastLevelSentAt) >= 0.1 else { return }
        session.lastLevelSentAt = current

        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        // RMS → 0～1（-60dB 以下为 0）。
        let db = 20 * log10(max(rms, 1e-6))
        let level = min(1, max(0, (db + 60) / 60))
        emit(.levelUpdated(level))
    }

    /// 设备配置变化：安全停止采集，已落盘内容保留，上报断开事件。
    private func handleConfigurationChange() {
        let current: CaptureSession? = lock.withLock {
            let current = session
            session = nil
            current?.isStopping = true
            return current
        }
        if let current {
            teardown(current)
            emit(.deviceDisconnected)
        }
    }

    /// 停引擎、摘回调、去观察者；AVAudioFile 随引用释放关闭。
    private func teardown(_ session: CaptureSession) {
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        if let observer = session.configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            session.configChangeObserver = nil
        }
    }

    private func emit(_ event: AudioCaptureEvent) {
        eventContinuation.yield(event)
    }
}

/// AVAudioConverter 输入块的消费标记（避免在并发闭包中直接捕获可变变量）。
private final class ConsumptionFlag: @unchecked Sendable {
    var consumed = false
}

// MARK: - CoreAudio 设备辅助

extension AVAudioCaptureService {
    /// 全部音频设备标识。
    static func inputAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// 系统默认输入设备。
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != 0 else { return nil }
        return id
    }

    /// 设备是否有输入流。
    static func deviceHasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    /// 设备名称。
    static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name?.takeUnretainedValue() as String?
    }

    /// 为引擎指定输入设备。
    static func assignInputDevice(_ id: AudioDeviceID, to engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw DictationError(
                category: .deviceUnavailable,
                userMessage: "音频引擎不可用，无法选择输入设备",
                isRetryable: false
            )
        }
        var deviceID = id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw DictationError(
                category: .deviceUnavailable,
                userMessage: "所选麦克风不可用，请重新选择输入设备"
            )
        }
    }
}
