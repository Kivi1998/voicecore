import OpenTypelessDomain

/// 口述状态的用户可读文案（App 层统一；菜单栏、悬浮条、历史共用口径）。
enum RecordStatusText {
    static func text(for status: DictationStatus) -> String {
        switch status {
        case .created, .queued: "准备中"
        case .recording: "录音中"
        case .audioSaved: "录音已保存"
        case .transcribing: "识别中"
        case .transcribed: "识别完成"
        case .rewriting: "改写中"
        case .ready: "待输入"
        case .injecting: "正在输入"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .recordingFailed: "录音失败"
        case .transcriptionFailed: "识别失败"
        case .rewriteFailed: "改写失败"
        case .injectionFailed: "输入失败"
        }
    }

    /// 失败阶段文案（历史页面区分转录/改写/输入阶段）。
    static func failureStageText(for status: DictationStatus) -> String? {
        switch status {
        case .transcriptionFailed: "语音识别"
        case .rewriteFailed: "文字改写"
        case .injectionFailed: "自动输入"
        case .recordingFailed: "录音"
        default: nil
        }
    }
}
