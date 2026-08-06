import Foundation

/// 领域核心包占位标记。
///
/// 本包只允许依赖 Foundation；不得导入 SwiftUI、AppKit、AVFoundation、GRDB
/// 或任何供应商实现。CORE-001 将在此定义跨 Apple 平台领域类型与状态枚举。
public enum OpenTypelessDomain {}
