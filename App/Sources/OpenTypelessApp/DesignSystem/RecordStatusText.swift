import OpenTypelessDomain

/// 口述状态的用户可读文案（App 层统一；菜单栏、悬浮条、历史共用口径）。
enum RecordStatusText {
    /// 状态文案表（替代长 switch，新增状态必须登记）。
    private static let texts: [DictationStatus: String] = [
        .created: "准备中",
        .queued: "准备中",
        .recording: "录音中",
        .audioSaved: "录音已保存",
        .transcribing: "识别中",
        .transcribed: "识别完成",
        .rewriting: "改写中",
        .ready: "待输入",
        .injecting: "正在输入",
        .completed: "已完成",
        .cancelled: "已取消",
        .recordingFailed: "录音失败",
        .transcriptionFailed: "识别失败",
        .rewriteFailed: "改写失败",
        .injectionFailed: "输入失败"
    ]

    /// 失败阶段文案表（历史页面区分转录/改写/输入阶段）。
    private static let failureStageTexts: [DictationStatus: String] = [
        .transcriptionFailed: "语音识别",
        .rewriteFailed: "文字改写",
        .injectionFailed: "自动输入",
        .recordingFailed: "录音"
    ]

    static func text(for status: DictationStatus) -> String {
        texts[status] ?? status.rawValue
    }

    /// 失败阶段文案；非失败状态返回 nil。
    static func failureStageText(for status: DictationStatus) -> String? {
        failureStageTexts[status]
    }
}
