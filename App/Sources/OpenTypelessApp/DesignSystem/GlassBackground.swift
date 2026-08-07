import SwiftUI

/// 系统玻璃与材质降级（UI-006）。
///
/// 规则（DESIGN.md §3.3、范围约束）：
/// - macOS 26+ 使用系统 Liquid Glass API（`.glassEffect`）；
/// - 旧系统降级为系统材质 `.regularMaterial`，绝不自制"假玻璃"；
/// - 「减少透明度」开启时使用不透明背景，保证可读；
/// - 「增加对比度」交给系统语义颜色自动适配。
struct GlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            // 减少透明度：不透明底，保证文字可读。
            Capsule().fill(.background)
                .shadow(radius: 2, y: 1)
        } else if #available(macOS 26.0, *) {
            // 系统原生 Liquid Glass。
            Capsule().fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            // 旧系统：原生视觉材质降级。
            Capsule().fill(.regularMaterial)
        }
    }
}

extension View {
    /// 胶囊形容器的系统玻璃背景（自动降级）。
    func glassCapsuleBackground() -> some View {
        background(GlassBackground())
    }
}

/// 减少动态：状态动画统一入口（UI-006）。
///
/// 「减少动态」开启时不附加显式动画（依赖系统默认的即时切换），
/// 避免眩晕；其余情况使用系统默认动画。
struct ReducedMotionAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transaction { transaction in
                transaction.animation = nil
            }
        } else {
            content
        }
    }
}

extension View {
    func respectsReducedMotion() -> some View {
        modifier(ReducedMotionAnimation())
    }
}
