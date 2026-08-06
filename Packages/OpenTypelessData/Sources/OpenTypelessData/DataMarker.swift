import Foundation
import OpenTypelessDomain

/// 数据持久化包占位标记。
///
/// DATA-001 起将在此引入 GRDB＋SQLite（锁定精确版本）、迁移、
/// 录音文件仓储和各仓储实现；GRDB 依赖只在数据任务中登记并锁定。
public enum OpenTypelessData {}
