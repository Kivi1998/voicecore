@testable import OpenTypelessDomain
import XCTest

final class DictationStateMachineTests: XCTestCase {
    /// 主路径：created → … → completed。
    func testHappyPath() {
        let path: [(DictationStatus, DictationStatus)] = [
            (.created, .recording),
            (.recording, .audioSaved),
            (.audioSaved, .transcribing),
            (.transcribing, .transcribed),
            (.transcribed, .rewriting),
            (.rewriting, .ready),
            (.ready, .injecting),
            (.injecting, .completed)
        ]
        for (from, to) in path {
            XCTAssertTrue(
                DictationStateMachine.canTransition(from: from, to: to),
                "\(from) → \(to) 必须合法"
            )
        }
    }

    /// 关闭改写：transcribed 直接 ready。
    func testRewriteDisabledPath() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .transcribed, to: .ready))
    }

    /// 转录失败重试：只允许重新转录，不得跳到改写或完成。
    func testTranscriptionRetry() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .transcriptionFailed, to: .transcribing))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .transcriptionFailed, to: .rewriting))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .transcriptionFailed, to: .ready))
    }

    /// 改写失败：可仅重新改写（不得重复上传音频），也可采用原文进入待输入。
    func testRewriteFailureRecovery() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .rewriteFailed, to: .rewriting))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .rewriteFailed, to: .ready))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .rewriteFailed, to: .transcribing))
    }

    /// 输入失败可再次输入；完成与取消为终态。
    func testInjectionRetryAndTerminals() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .injectionFailed, to: .injecting))
        XCTAssertTrue(DictationStateMachine.isTerminal(.completed))
        XCTAssertTrue(DictationStateMachine.isTerminal(.cancelled))
        XCTAssertTrue(DictationStateMachine.isTerminal(.recordingFailed))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .completed, to: .injecting))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .cancelled, to: .recording))
    }

    /// 取消只能在采集前或采集中发生。
    func testCancellation() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .created, to: .cancelled))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .queued, to: .cancelled))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .recording, to: .cancelled))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .transcribing, to: .cancelled))
        XCTAssertFalse(DictationStateMachine.canTransition(from: .injecting, to: .cancelled))
    }

    /// 启动恢复专用转移（ARCHITECTURE §5.1）。
    func testRecoveryTransitions() {
        XCTAssertTrue(DictationStateMachine.canTransition(from: .created, to: .audioSaved))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .created, to: .recordingFailed))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .recording, to: .audioSaved))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .transcribed, to: .rewriteFailed))
        XCTAssertTrue(DictationStateMachine.canTransition(from: .ready, to: .injectionFailed))
    }

    /// 全量矩阵：非法迁移一律被拒绝（15×15 全枚举）。
    func testAllIllegalTransitionsRejected() {
        // 有向边（迁移有方向，不能用无序 Set 表示）。
        struct Edge: Hashable {
            let from: DictationStatus
            let to: DictationStatus
        }
        func e(_ from: DictationStatus, _ to: DictationStatus) -> Edge {
            Edge(from: from, to: to)
        }
        let legal: Set<Edge> = [
            e(.created, .queued), e(.created, .recording), e(.created, .cancelled),
            e(.created, .audioSaved), e(.created, .recordingFailed),
            e(.queued, .recording), e(.queued, .transcribing), e(.queued, .cancelled),
            e(.queued, .audioSaved), e(.queued, .recordingFailed),
            e(.recording, .audioSaved), e(.recording, .recordingFailed), e(.recording, .cancelled),
            e(.audioSaved, .queued), e(.audioSaved, .transcribing),
            e(.transcribing, .transcribed), e(.transcribing, .transcriptionFailed),
            e(.transcriptionFailed, .transcribing),
            e(.transcribed, .rewriting), e(.transcribed, .ready), e(.transcribed, .rewriteFailed),
            e(.rewriting, .ready), e(.rewriting, .rewriteFailed),
            e(.rewriteFailed, .rewriting), e(.rewriteFailed, .ready),
            e(.ready, .injecting), e(.ready, .injectionFailed), e(.ready, .completed),
            e(.injecting, .completed), e(.injecting, .injectionFailed),
            e(.injectionFailed, .injecting)
        ]
        for from in DictationStatus.allCases {
            for to in DictationStatus.allCases {
                let expected = legal.contains(Edge(from: from, to: to))
                XCTAssertEqual(
                    DictationStateMachine.canTransition(from: from, to: to),
                    expected,
                    "\(from.rawValue) → \(to.rawValue) 判定错误"
                )
                if !expected {
                    XCTAssertThrowsError(
                        try DictationStateMachine.validateTransition(from: from, to: to)
                    )
                }
            }
        }
    }

    /// 相同状态不得原地迁移。
    func testSelfTransitionRejected() {
        for status in DictationStatus.allCases {
            XCTAssertFalse(DictationStateMachine.canTransition(from: status, to: status))
        }
    }
}
