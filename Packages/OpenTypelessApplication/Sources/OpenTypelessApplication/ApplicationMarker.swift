import Foundation
import OpenTypelessDomain

/// 应用服务层占位标记。
///
/// 口述会话编排、历史、统计、词典、设置与重试恢复服务将在此实现，
/// 只依赖 Domain 中的实体与服务协议，不直接调用平台或供应商实现。
public enum OpenTypelessApplication {}
