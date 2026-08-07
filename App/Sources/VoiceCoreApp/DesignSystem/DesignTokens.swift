import SwiftUI

/// Apple 原生设计系统（UI-001）。
///
/// 规则（`DESIGN.md` §5–§7）：
/// - 字体只使用系统语义字体；数据用等宽数字特性；
/// - 颜色只使用系统语义颜色与强调色，不硬编码品牌色；
/// - 间距使用 4 点基础网格；
/// - 图标仅使用 SF Symbols 且必须带可访问标签。
enum DesignTokens {
    /// 间距（4 点基础网格）。
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    /// 语义字体。
    enum Font {
        static let largeTitle: SwiftUI.Font = .largeTitle
        static let title: SwiftUI.Font = .title2
        static let headline: SwiftUI.Font = .headline
        static let body: SwiftUI.Font = .body
        static let callout: SwiftUI.Font = .callout
        static let caption: SwiftUI.Font = .caption
        /// 数据数值（等宽数字）。
        static func numeric(_ style: SwiftUI.Font = .title2) -> SwiftUI.Font {
            style.monospacedDigit()
        }
    }

    /// 语义颜色（状态同时配合图标与文字，颜色不是唯一通道）。
    enum Color {
        static let secondaryText: SwiftUI.Color = .secondary
        static let success: SwiftUI.Color = .green
        static let warning: SwiftUI.Color = .orange
        static let failure: SwiftUI.Color = .red
    }
}

/// 图标与可访问标签的配对（图标按钮必须使用）。
struct DSIcon {
    let symbol: String
    let accessibilityLabel: String

    static let record = DSIcon(symbol: "mic.fill", accessibilityLabel: "开始录音")
    static let stop = DSIcon(symbol: "stop.fill", accessibilityLabel: "停止录音")
    static let history = DSIcon(symbol: "clock.arrow.circlepath", accessibilityLabel: L10n.Page.history)
    static let dictionary = DSIcon(symbol: "character.book.closed", accessibilityLabel: L10n.Page.dictionary)
    static let settings = DSIcon(symbol: "gear", accessibilityLabel: L10n.Page.settings)
    static let home = DSIcon(symbol: "house", accessibilityLabel: L10n.Page.dashboard)
    static let copy = DSIcon(symbol: "doc.on.doc", accessibilityLabel: "复制")
    static let download = DSIcon(symbol: "arrow.down.circle", accessibilityLabel: "下载录音")
    static let favorite = DSIcon(symbol: "star", accessibilityLabel: "收藏")
    static let favoriteFill = DSIcon(symbol: "star.fill", accessibilityLabel: "取消收藏")
    static let delete = DSIcon(symbol: "trash", accessibilityLabel: L10n.Common.delete)
    static let retry = DSIcon(symbol: "arrow.clockwise", accessibilityLabel: L10n.Common.retry)
    static let play = DSIcon(symbol: "play.circle", accessibilityLabel: "播放录音")
    static let search = DSIcon(symbol: "magnifyingglass", accessibilityLabel: "搜索")
    static let add = DSIcon(symbol: "plus", accessibilityLabel: L10n.Common.add)
    static let success = DSIcon(symbol: "checkmark.circle.fill", accessibilityLabel: "成功")
    static let failure = DSIcon(symbol: "exclamationmark.circle.fill", accessibilityLabel: "失败")
    static let warning = DSIcon(symbol: "exclamationmark.triangle.fill", accessibilityLabel: "警告")
}

/// 设计系统图标视图：SF Symbol＋可访问标签（图标按钮统一使用）。
struct DSIconImage: View {
    let icon: DSIcon

    var body: some View {
        Image(systemName: icon.symbol)
            .accessibilityLabel(Text(icon.accessibilityLabel))
    }
}
