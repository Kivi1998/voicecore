import SwiftUI

/// 轻量通知组件（UI-004）：页面顶部短暂提示，成功/失败语义，
/// 图标＋文字（颜色不是唯一通道），VoiceOver 可朗读。
struct ToastView: View {
    enum Kind {
        case success
        case failure
        case info

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .failure: "exclamationmark.circle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: DS.Color.success
            case .failure: DS.Color.failure
            case .info: .accentColor
            }
        }
    }

    let kind: Kind
    let message: String

    var body: some View {
        Label(message, systemImage: kind.symbol)
            .font(DS.Font.callout)
            .foregroundStyle(kind.color)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

/// 通知修饰器：展示 message 后自动消失。
struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    /// 展示时长（秒）。
    var duration: TimeInterval = 2.4

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    ToastView(kind: message.kind, message: message.text)
                        .padding(.top, DS.Spacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: message?.id)
    }
}

/// 通知内容。
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let kind: ToastView.Kind
    let text: String

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    /// 绑定 ToastMessage 即获得页面内通知能力。
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// 日期范围筛选控件（UI-004）：起止日期＋清除。
struct DateRangeFilter: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DatePicker(
                "开始",
                selection: startBinding,
                displayedComponents: .date
            )
            .labelsHidden()
            DatePicker(
                "结束",
                selection: endBinding,
                displayedComponents: .date
            )
            .labelsHidden()
            if startDate != nil || endDate != nil {
                Button("清除") {
                    startDate = nil
                    endDate = nil
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清除日期筛选")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按日期范围筛选")
    }

    /// Optional 绑定桥接（未选择时以今天占位，用户改动即生效）。
    private var startBinding: Binding<Date> {
        Binding(
            get: { startDate ?? Date() },
            set: { startDate = $0 }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { endDate ?? Date() },
            set: { endDate = $0 }
        )
    }
}
