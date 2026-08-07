import Foundation

/// 界面文案集中定义（UI-005）。
///
/// 首版界面语言为简体中文；全部跨页通用文案集中在 `L10n`，
/// 页面内一次性文案就近书写但禁止散落重复。英文扩展结构：
/// 迁移到 String Catalog（FND-001 Xcode 工程建立后）时，
/// 以这里的键名作为本地化键，页面代码不需改动。
///
/// 中英文长度变化不破版由布局保证（无固定宽度文案容器，
/// 侧栏宽度交给系统约束）。
enum L10n {
    enum Common {
        static let cancel = "取消"
        static let save = "保存"
        static let delete = "删除"
        static let edit = "编辑"
        static let retry = "重试"
        static let add = "添加"
        static let unconfigured = "未配置"
    }

    enum Action {
        static let copied = "已复制到剪贴板"
        static let audioExported = "录音已导出"
        static let favorited = "已收藏"
        static let unfavorited = "已取消收藏"
        static let retryTranscription = "重新识别"
        static let retryRewriteOnly = "仅重新改写"
        static let retryInjection = "再次输入"
    }

    enum Page {
        static let dashboard = "首页"
        static let history = "历史记录"
        static let dictionary = "词典"
        static let settings = "设置"
    }

    enum Settings {
        static let general = "通用"
        static let providers = "模型"
        static let storage = "数据与存储"
    }
}
