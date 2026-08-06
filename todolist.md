# OpenTypeless 可执行待办

本文件与 `tasklist.md` 的任务 ID 一一对应。勾选表示代码、测试、文档和该任务验收标准全部完成并已合并；仅“代码写完”不得勾选。

## G0：工程基线

- [ ] FND-001 初始化 SwiftUI＋AppKit 原生 macOS 项目
- [ ] FND-002 建立 App、Features 与 Swift Packages 依赖边界
- [ ] FND-003 配置 SwiftFormat、SwiftLint、严格并发检查和统一命令
- [ ] FND-004 建立配置分层与敏感日志规范
- [ ] FND-005 配置 Swift/Xcode CI 和 ARM64 Archive 冒烟

## G1：接口和数据结构冻结

- [ ] CORE-001 定义跨 Apple 平台领域类型
- [ ] DATA-001 使用 GRDB 设计 SQLite 架构、索引和迁移
- [ ] DATA-002 实现口述记录仓储
- [ ] DATA-003 实现录音文件持久化
- [ ] STT-001 定义语音识别适配器契约
- [ ] LLM-001 定义文字改写适配器契约
- [ ] PLAT-001 定义跨平台能力接口

## G2：核心口述闭环

- [ ] CORE-002 实现口述状态机
- [ ] CORE-003 实现耐久化作业队列和启动恢复
- [ ] CORE-004 编排录音、转录和改写流水线
- [ ] CORE-005 实现自动输入与剪贴板恢复编排
- [ ] DATA-004 实现词典仓储
- [ ] DATA-005 实现模型与应用设置仓储
- [ ] STT-002 使用 URLSession 实现 OpenAI 兼容语音转录
- [ ] STT-003 实现语音提示、取消、重试和错误归一化
- [ ] STT-004 实现语音模型连接测试
- [ ] LLM-002 使用 URLSession 实现 OpenAI 兼容文字改写
- [ ] LLM-003 使用 URLSession 实现 Anthropic 兼容文字改写
- [ ] LLM-004 实现默认提示词、关闭改写和连接测试
- [ ] PLAT-002 使用 AppKit 实现按一次开始、再按一次停止的全局快捷键
- [ ] PLAT-003 使用 AVFoundation 实现麦克风录音、编码和中断处理
- [ ] PLAT-004 使用 Accessibility API 实现辅助功能权限与自动输入
- [ ] PLAT-005 使用 MenuBarExtra、NSPanel 实现菜单栏和无焦点悬浮条

## G3：产品页面与完整功能

- [ ] CORE-006 实现中英混合统计和聚合
- [ ] DATA-006 实现删除、导出和存储统计
- [ ] STT-005 建立千问、豆包原生适配扩展骨架
- [ ] PLAT-006 实现系统权限引导、SMAppService 开机启动和单实例
- [ ] PLAT-007 编写 iPhone、iPad 共享包与键盘扩展边界说明
- [ ] UI-001 建立 SwiftUI 原创设计系统和 SF Symbols 规范
- [ ] UI-002 使用 NavigationSplitView 实现应用壳、导航和通用状态
- [ ] UI-003 实现首页统计与最近记录
- [ ] UI-004 实现通用弹窗、菜单、表单和通知组件
- [ ] UI-005 建立界面国际化结构
- [ ] UI-006 实现原生 Liquid Glass、旧系统材质降级和辅助功能响应
- [ ] HIST-001 实现历史查询服务
- [ ] HIST-002 实现历史列表与详情
- [ ] HIST-003 实现复制、下载、收藏和删除
- [ ] HIST-004 实现失败提示、重新转录和重新改写
- [ ] HIST-005 优化历史大数据量性能
- [ ] DICT-001 实现词典服务与输入规范化
- [ ] DICT-002 实现词典页面和添加交互
- [ ] DICT-003 将词典注入语音和改写提示
- [ ] SET-001 实现应用设置服务和默认值
- [ ] SET-002 实现语音模型配置页
- [ ] SET-003 实现文字改写模型配置页
- [ ] SET-004 实现录音存储、清理和导出设置

## G4：审查、测试和发布候选

- [ ] TEST-001 建立 Swift Package、GRDB 和 URLSession 测试矩阵
- [ ] TEST-002 建立 SwiftUI、快照和 XCUITest 测试
- [ ] TEST-003 建立模型协议契约测试和模拟服务器
- [ ] TEST-004 在真实 Apple Silicon Mac 执行端到端验收
- [ ] TEST-005 完成代码、安全、隐私和性能审查并登记缺陷
- [ ] TEST-007 验收 Liquid Glass、旧系统降级、VoiceOver、键盘、对比度及减少透明度/动态
- [ ] REL-001 构建 ARM64 应用和 DMG
- [ ] REL-002 在全新 macOS 用户账户验证安装与卸载

## G5：缺陷闭环与最终交付

- [ ] TEST-006 修复缺陷并完成全量回归验证
- [ ] REL-003 完成用户、开发和故障排查文档
- [ ] REL-004 生成校验值、发布说明和最终验收记录

## 最终人工核对（不新增任务 ID）

- [ ] 所有 `tasklist.md` 任务 ID 均已勾选，且依赖任务先于下游任务完成
- [ ] 仓库全文搜索确认不存在登录、账号、会员、套餐、订阅或额度功能
- [ ] 数据库中 API 密钥可正常使用，界面与日志不会意外显示完整值
- [ ] 成功和失败录音均永久保留，只有明确删除才移除
- [ ] Kimi 完成开发后，由独立审查 Agent 执行 TEST-005，而非由原开发 Agent 自审
- [ ] 审查发现的问题交回对应模块 Agent 修复，并由独立 Agent 执行 TEST-006 回归
- [ ] DMG 在未安装开发工具的真实 Apple Silicon Mac 或干净用户账户验收通过
