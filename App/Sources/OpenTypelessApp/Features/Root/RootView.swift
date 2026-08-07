import SwiftUI

/// 侧栏页面。
enum AppPage: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case history
    case dictionary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L10n.Page.dashboard
        case .history: L10n.Page.history
        case .dictionary: L10n.Page.dictionary
        }
    }

    var icon: DSIcon {
        switch self {
        case .dashboard: .home
        case .history: .history
        case .dictionary: .dictionary
        }
    }
}

/// 应用壳：NavigationSplitView 侧栏＋详情（UI-002）。
///
/// 侧栏宽度由系统布局约束控制；页面切换保持键盘焦点与
/// VoiceOver 顺序（原生导航语义）。
struct RootView: View {
    let composition: AppComposition
    @State private var selection: AppPage? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.icon.symbol)
                    .accessibilityLabel(page.icon.accessibilityLabel)
                    .tag(page)
            }
            .navigationTitle("OpenTypeless")
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView(composition: composition)
            case .history:
                HistoryView(composition: composition)
            case .dictionary:
                DictionaryView(composition: composition)
            }
        }
        .onReceive(composition.$requestedPage) { page in
            guard let page else { return }
            selection = page
            composition.requestedPage = nil
        }
    }
}
