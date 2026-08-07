import Foundation
import OpenTypelessDomain

/// 口述会话编排器：唯一推进口述状态机的模块。
///
/// 职责（`docs/ARCHITECTURE.md` §4.2）：
/// 1. 开始录音前创建数据库记录和录音目标文件；
/// 2. 音频持续写盘（由 AudioCapture/AudioFileStore 保证）；
/// 3. 停止后：关闭校验文件 → 语音识别 → 保存原始转录 → 可选改写
///    → 保存最终文字 → 自动输入；
/// 4. 每一步均持久化状态、错误类别和时间，尝试记录完整写回；
/// 5. 同一时刻最多一个活跃录音会话；
/// 6. 自动输入失败不回滚转录结果。
///
/// 实现分三个文件：本文件为会话控制与内部助手，
/// `DictationOrchestrator+Pipeline.swift` 为主流水线各阶段，
/// `DictationOrchestrator+Retry.swift` 为重试入口。
public actor DictationOrchestrator {
    let records: any DictationRecordRepository
    let audioFiles: any AudioFileStore
    let audioCapture: any AudioCapture
    let providerFactory: any ProviderFactory
    let optionsProvider: any PipelineOptionsProvider
    let clipboard: any ClipboardService
    let injector: any TextInjector
    let audioURLResolver: @Sendable (String) throws -> URL
    let now: @Sendable () -> Date

    /// 当前活跃会话记录标识（录音中或处理中）。
    public internal(set) var activeRecordID: UUID?

    private let eventStream: AsyncStream<DictationSessionEvent>
    private let eventContinuation: AsyncStream<DictationSessionEvent>.Continuation

    /// 会话事件流；界面据此更新录音胶囊与状态。
    public nonisolated var events: AsyncStream<DictationSessionEvent> {
        eventStream
    }

    /// 依赖注入组合根；全部协作者经协议解耦，测试可用内存替身组装。
    public init(
        records: any DictationRecordRepository,
        audioFiles: any AudioFileStore,
        audioCapture: any AudioCapture,
        providerFactory: any ProviderFactory,
        optionsProvider: any PipelineOptionsProvider,
        clipboard: any ClipboardService,
        injector: any TextInjector,
        audioURLResolver: @escaping @Sendable (String) throws -> URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.records = records
        self.audioFiles = audioFiles
        self.audioCapture = audioCapture
        self.providerFactory = providerFactory
        self.optionsProvider = optionsProvider
        self.clipboard = clipboard
        self.injector = injector
        self.audioURLResolver = audioURLResolver
        self.now = now
        let (stream, continuation) = AsyncStream<DictationSessionEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation
    }

    // MARK: - 录音控制

    /// 按一次快捷键：开始录音。
    ///
    /// 先建库记录与目标文件再开始采集；已有活跃会话时明确拒绝。
    /// - Returns: 新记录标识。
    @discardableResult
    public func startRecording() async throws -> UUID {
        guard activeRecordID == nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "已有录音进行中",
                isRetryable: false
            )
        }
        guard let (_, snapshot) = try await providerFactory.makeSpeechProvider() else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "尚未配置语音识别模型，请先前往设置完成配置",
                isRetryable: false
            )
        }

        let startedAt = now()
        let recordID = UUID()
        let relativePath = try audioFiles.prepareDestination(
            recordID: recordID,
            startedAt: startedAt,
            fileExtension: "m4a"
        )
        let record = DictationRecord(
            id: recordID,
            status: .created,
            startedAt: startedAt,
            audioRelativePath: relativePath,
            audioMimeType: "audio/mp4",
            speechSnapshot: snapshot,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        try await records.create(record)

        do {
            try await audioCapture.start(deviceID: nil, writingTo: relativePath)
        } catch let error as DictationError {
            try? await transition(recordID: recordID, to: .recordingFailed, error: error)
            emit(.sessionFinished(recordID: recordID, status: .recordingFailed))
            throw error
        }
        try await transition(recordID: recordID, to: .recording)
        activeRecordID = recordID
        return recordID
    }

    /// 再按一次快捷键：结束录音并异步执行转录→改写→输入流水线。
    public func stopRecording() async {
        guard let recordID = activeRecordID else { return }
        Task {
            await runPipeline(recordID: recordID)
        }
    }

    /// Esc 取消当前录音：安全关闭文件，记录标记取消（录音保留）。
    public func cancelRecording() async {
        guard let recordID = activeRecordID else { return }
        await audioCapture.cancel()
        activeRecordID = nil
        try? await transition(recordID: recordID, to: .cancelled)
        emit(.sessionFinished(recordID: recordID, status: .cancelled))
    }

    // MARK: - 内部助手

    func guardIdle() throws {
        guard activeRecordID == nil else {
            throw DictationError(
                category: .configurationInvalid,
                userMessage: "已有录音进行中，请稍后重试",
                isRetryable: false
            )
        }
    }

    func transition(
        recordID: UUID,
        to target: DictationStatus,
        error: DictationError? = nil
    ) async throws {
        guard let current = try await records.get(id: recordID) else { return }
        try DictationStateMachine.validateTransition(from: current.status, to: target)
        try await records.updateStatus(id: recordID, status: target, error: error, at: now())
        emit(.statusChanged(recordID: recordID, status: target))
    }

    func saveFinalText(recordID: UUID, finalText: String) async throws {
        var record = try await requireRecord(recordID)
        record.finalText = finalText
        record.countUnits = UnitCounter.count(finalText)
        record.updatedAt = now()
        try await records.save(record)
    }

    func requireRecord(_ id: UUID) async throws -> DictationRecord {
        guard let record = try await records.get(id: id) else {
            throw DictationError(category: .unknown, userMessage: "记录不存在", isRetryable: false)
        }
        return record
    }

    /// 录音/文件阶段失败兜底：仅在仍处于早期状态时落库 recordingFailed。
    func failRecordingStage(recordID: UUID, error: Any) async {
        guard let record = try? await records.get(id: recordID) else { return }
        guard record.status == .recording || record.status == .created else { return }
        let mapped = (error as? DictationError) ?? DictationError(
            category: .unknown,
            userMessage: "录音处理发生未知错误"
        )
        try? await transition(recordID: recordID, to: .recordingFailed, error: mapped)
    }

    func emitTerminal(recordID: UUID) async {
        if let record = try? await records.get(id: recordID) {
            emit(.sessionFinished(recordID: recordID, status: record.status))
        }
    }

    func emit(_ event: DictationSessionEvent) {
        eventContinuation.yield(event)
    }
}
