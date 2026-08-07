@testable import VoiceCoreApp
import XCTest

/// L10n 文案键完整性测试（TEST-002）：防空串、防页面标题撞车。
final class L10nTests: XCTestCase {
    func testCommonStringsNonEmpty() {
        let values = [
            L10n.Common.cancel, L10n.Common.save, L10n.Common.delete,
            L10n.Common.edit, L10n.Common.retry, L10n.Common.add,
            L10n.Common.unconfigured
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty)
        }
    }

    func testActionStringsNonEmpty() {
        let values = [
            L10n.Action.copied, L10n.Action.audioExported,
            L10n.Action.favorited, L10n.Action.unfavorited,
            L10n.Action.retryTranscription, L10n.Action.retryRewriteOnly,
            L10n.Action.retryInjection
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty)
        }
    }

    /// 四个页面标题互不相同（侧栏/窗口标题依赖此唯一性）。
    func testPageTitlesUnique() {
        let titles = [
            L10n.Page.dashboard, L10n.Page.history,
            L10n.Page.dictionary, L10n.Page.settings
        ]
        XCTAssertEqual(Set(titles).count, titles.count, "页面标题存在重复")
        for title in titles {
            XCTAssertFalse(title.isEmpty)
        }
    }

    func testSettingsGroupLabelsNonEmptyAndUnique() {
        let labels = [L10n.Settings.general, L10n.Settings.providers, L10n.Settings.storage]
        XCTAssertEqual(Set(labels).count, labels.count, "设置分组标签存在重复")
        for label in labels {
            XCTAssertFalse(label.isEmpty)
        }
    }
}
