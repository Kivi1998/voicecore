import SwiftUI

/// 通用空 / 载入 / 错误状态组件（UI-002）。
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message {
                Text(message)
            }
        }
    }
}

/// 通用错误状态（带重试入口）。
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button(L10n.Common.retry, action: retry)
            }
        }
    }
}

/// 数值统计卡（首页；不过度卡片化，仅真实信息组）。
struct StatCard: View {
    let title: String
    let value: Int64
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Font.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(value, format: .number)
                    .font(DS.Font.numeric(.title))
                Text(unit)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
