@testable import VoiceCoreApp
import VoiceCoreDomain
import XCTest

/// RecordStatusText 状态文案表测试（TEST-002）。
final class RecordStatusTextTests: XCTestCase {
    /// 全部 15 个状态都必须有非空用户可读文案（新增状态漏登记会被本测试拦住）。
    func testEveryStatusHasNonEmptyText() {
        for status in DictationStatus.allCases {
            XCTAssertFalse(
                RecordStatusText.text(for: status).isEmpty,
                "\(status.rawValue) 缺少状态文案"
            )
        }
    }

    /// 失败阶段文案只给四个失败状态，其余状态一律为 nil。
    func testFailureStageOnlyForFailedStatuses() {
        let failed: [DictationStatus] = [
            .recordingFailed, .transcriptionFailed, .rewriteFailed, .injectionFailed
        ]
        for status in failed {
            let stage = RecordStatusText.failureStageText(for: status)
            XCTAssertNotNil(stage, "\(status.rawValue) 缺少失败阶段文案")
            XCTAssertFalse(stage?.isEmpty ?? true)
        }
        for status in DictationStatus.allCases where !failed.contains(status) {
            XCTAssertNil(
                RecordStatusText.failureStageText(for: status),
                "\(status.rawValue) 不应有失败阶段文案"
            )
        }
    }

    /// 失败阶段文案与各阶段一一对应（历史页面展示口径）。
    func testFailureStageTextsMatchStages() {
        XCTAssertEqual(RecordStatusText.failureStageText(for: .recordingFailed), "录音")
        XCTAssertEqual(RecordStatusText.failureStageText(for: .transcriptionFailed), "语音识别")
        XCTAssertEqual(RecordStatusText.failureStageText(for: .rewriteFailed), "文字改写")
        XCTAssertEqual(RecordStatusText.failureStageText(for: .injectionFailed), "自动输入")
    }
}
