# OpenTypeless 静态审查报告（TEST-005）

> **性质声明**：本报告是开发方（Kimi）按 `docs/REVIEW_AND_QA.md` §4/§5 清单执行的**静态自审查**，用于提前暴露问题。
> 按流程要求，正式 TEST-005 必须由独立审查角色（Codex）执行，本报告**不能替代**独立审查；
> `todolist.md` 中 TEST-005 行保持未勾选。

- 审查人：Kimi（开发方自审）
- 日期：2026-08-07
- 代码基线：`main` @ 5020b36
- 审查方式：纯静态（逐条清单核对＋全仓 grep 扫描＋`swift build` 编译验证）
- 环境限制：B-001（本机仅 CLT 26.6，无完整 Xcode），无法执行任何测试、无法构建 `.app`、无法做运行时验证

## 一、需求完整性（清单 4.1）

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| 无登录/注册/会员/订阅/邀请码/额度/广告/云同步 | 通过 | 全仓 grep 仅命中「登录时自动启动」（开机启动 Toggle，属需求内功能） |
| 今日/当周/累计统计口径（中英混合计数） | 通过（代码级） | `StatisticsService`＋固定 GMT+8 日历测试用例；统计只计 final_text 非空记录；测试未执行（D-01） |
| 历史支持任意日期、搜索、状态、收藏、复制、下载、删除、重试 | 通过（代码级） | `HistoryView`/`HistoryViewModel`：DateRangeFilter、`.searchable`、状态徽章筛选、行内操作；仓储组合筛选＋双键游标分页 |
| 成功和失败录音默认永久保留 | 通过（代码级） | 无自动清理路径；唯一批量删除入口需二次确认（SettingsView confirmationDialog）；删除先删文件再删库 |
| 转录/改写/自动输入失败分别处理 | 通过（代码级） | 状态机 `transcriptionFailed`/`rewriteFailed`/`injectionFailed` 三态分离，重试入口各只回退到对应阶段 |
| 词典为单词级手动维护并进入模型请求 | 通过（代码级） | `DictionaryView` 手动增删；`ProviderFactory.vocabularyTerms()` 进入语音提示与改写上下文 |
| 自动输入默认开启且有失败恢复路径 | 通过（代码级） | `PipelineOptions.autoInsert` 默认 `true`；`retryInjection` 仅接受 `injectionFailed` 且不影响最终文字与统计 |

## 二、架构一致性（清单 4.2）

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| 主界面 SwiftUI，系统集成 AppKit/原生框架；无 Web 技术栈 | 通过 | `App/Sources` 全部 SwiftUI；AppKit 仅用于 NSSavePanel/NSWorkspace 等必要桥接；无 React/Vue/Tauri/Electron/WebView |
| SwiftUI 视图不持有密钥、不承担耐久性与协议拼装 | 通过 | 密钥只经 `secrets(id:)` 通道（ViewModel 只接触掩码）；录音落盘在 Data 层；协议拼装在 Providers 层 |
| 业务核心/平台协议/macOS 实现边界清晰 | 通过 | Domain（纯 Foundation）→ Application → Data/Providers；Platform 实现 Domain 协议；App 经组合根装配 |
| 厂商协议逻辑收敛在适配器 | 通过 | OpenAI 语音、OpenAI 改写、Anthropic 改写各自独立适配器；注册机制可新增厂商 |
| 业务核心不依赖 AppKit | 通过 | Domain/Application/Data/Providers 四包无 AppKit import（编译验证） |
| 第三方依赖必要性与许可证 | 通过 | 仅 GRDB 7.11.1（MIT，D-017 已确认选型），`Package.resolved` 已锁定提交；无二进制依赖 |
| 并发隔离明确 | 通过（代码级） | 状态机与仓储为 actor；UI 在 MainActor；Platform 系统服务以 `@unchecked Sendable` 包装非 Sendable 系统 API（见 D-05） |
| 唯一可信状态源 | 通过 | 统一 `DictationError`/`ErrorCategory`（16 类）、`DictationStatus`（15 态）、仓储为唯一记录读写入口 |
| 无巨型模块/循环依赖/隐式全局状态/无界队列 | 通过（代码级） | SwiftPM 依赖图无环（编译验证）；会话级状态在编排器内；无全局可变单例 |
| Liquid Glass 用系统 API 并有降级 | 通过（编译级） | `GlassBackground`/`CapsuleGlassBackground`：macOS 26 `.glassEffect`、旧系统 `.regularMaterial`、Reduce Transparency 不透明底；运行期未验证（D-02） |

## 三、代码可靠性（清单 4.3）

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| `fatalError`/`preconditionFailure`/`try!` | 通过 | 全仓业务源码零命中（仅一处注释说明不得使用） |
| 强制解包/强制转换 | 基本通过 | 仅 1 处 `as! AXUIElement`（`AccessibilityTextInjector.swift:62`，受 `AXUIElementCopyAttributeValue` 成功返回保护），见 D-04 |
| `@unchecked Sendable` / `nonisolated(unsafe)` | 需独立复核 | 6 个 Platform 系统服务＋`FileAudioWriter`＋测试 Fake 使用 `@unchecked Sendable`；`nonisolated(unsafe)` 零命中。见 D-05 |
| 网络超时与重试上限 | 通过（代码级） | `HTTPClient` 每请求 `timeoutInterval`（配置化）；重试装饰器只重试瞬态故障（限流一次，取消/认证不重试） |
| 文件/数据库并发、重复点击、重复事件 | 通过（代码级） | 录音写 `.partial` 半成品 finalize 改名；状态机转移幂等防重复事件；按钮在进行中禁用 |
| 资源生命周期 | 通过（代码级） | AVAudioEngine/Carbon HotKey/AX/Task 均有 stop/deinit 路径；未运行验证（D-02） |
| 删除路径校验 | 通过（代码级） | 音频删除仅作用于数据根目录内相对路径，先删文件再删库 |

## 四、安全与隐私（清单 §5）

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| 数据库及父目录仅当前用户可访问 | 通过（代码级） | 数据目录/文件创建设 0700/0600 权限；测试覆盖但未执行（D-01） |
| 日志/状态/通知/快照/导出无完整密钥 | 通过（代码级） | `LogRedactor` 脱敏 `Authorization`/`x-api-key`/`sk-` 形态；导出 JSON v1 不含密钥与路径；配置查询默认返回掩码 |
| 空掩码不覆盖真实密钥 | 通过（代码级） | `ProviderProfileStore`：`apiKeyUpdate == nil` 保持原值（测试已编写） |
| Git 历史/脚本/示例/夹具无真实密钥 | 通过 | 全仓 grep 仅命中测试假密钥（`sk-test-*` 等夹具字符串）；`.env.example` 刻意无密钥变量 |
| 无未声明遥测/崩溃上传/更新检查 | 通过 | 网络出口仅用户配置的模型端点 |
| 普通导出不包含模型配置与密钥 | 通过（代码级） | 导出仅历史记录字段 |

## 五、缺陷登记

> 等级定义见 `docs/REVIEW_AND_QA.md` §13。本自审未发现严重级缺陷；D-01/D-02 属「验证缺失」而非代码缺陷，但按流程必须登记并在 Xcode 就绪后清零。

| 编号 | 等级 | 描述 | 处置计划 |
| --- | --- | --- | --- |
| D-01 | 高（验证缺失） | 约 100 个 XCTest（Domain/Data/Providers/Application 四包）已编写但**从未执行**；测试代码本身可能含编译错误 | Xcode 安装后第一件事 `make test-packages` 全量执行并修复 |
| D-02 | 高（验证缺失） | 全部平台代码（AVAudioEngine 录音、Carbon 快捷键、AX 自动输入、SMAppService、权限引导）与 `.glassEffect` 运行期行为**仅编译验证**，未在 macOS 26 真机/旧系统运行 | TEST-004/007 真机矩阵 |
| D-03 | 中 | 菜单栏「打开主窗口」接线不完整：`openMainWindowHandler` 目前只 activate 应用，未调用 `openWindow(id:)`，主窗口关闭后从菜单栏无法重开 | FND-001 Xcode 工程阶段补齐并验证 |
| D-04 | 低 | `AccessibilityTextInjector.swift:62` 使用 `as! AXUIElement`，虽受 API 契约保护，建议改条件转换防未来回归 | 随 TEST-006 修复 |
| D-05 | 低（待复核） | 6 处 `@unchecked Sendable`（Platform 系统服务包装非 Sendable 系统 API）＋`FileAudioWriter`，内部以锁/串行队列保护；需独立审查确认充分性 | 独立审查重点项 |
| D-06 | 中（验证缺失） | HIST-005 大数据量性能（数万条历史下分页/搜索/启动）未实测；数据集构造属 §6 要求 | TEST-004 阶段构造数据集实测 |
| D-07 | 中（验证缺失） | FND-005 GitHub CI workflow 已提交但**从未运行**；`xcodebuild` 路径与版本需首次运行校准 | 首次推送后校准并记录 |
| D-08 | 低 | String Catalog 未建立：当前为 L10n 键结构（跨页通用文案已收敛 37 处引用），页面内一次性文案仍为字面量 | 随 FND-001 迁移至 .xcstrings |
| D-09 | 低（待复核） | `SettingsView` 的 TabView 内 `ProviderSettingsView(composition: viewModelComposition)` 经 `compositionForChildren` 暴露组合根，可行但建议独立审查确认无循环持有 | 独立审查重点项 |

## 六、审查前置条件自评（清单 §2）

| 条件 | 状态 |
| --- | --- |
| tasklist 任务满足验收标准 | 部分：业务代码完成，Xcode 相关验收全部待 B-001 |
| todolist 无未说明的进行中任务、完成项有验证证据 | 满足（验证证据以编译通过＋测试代码就绪的 interim 形式登记） |
| 工作树无来源不明生成文件/密钥/录音样本 | 满足（git status 干净） |
| 格式化/静态检查/单元测试/集成测试/生产构建通过 | **不满足**：swiftformat/swiftlint 本机未安装；测试不可执行；生产构建待 Xcode |
| 迁移可从空库执行＋旧版本升级路径测试 | 测试已编写未执行（首版无已发布旧版本） |
| 提供 .app/.dmg 或可复现构建命令 | 部分：`make build-packages` 可复现；`.app` 待 Xcode |
| 已知缺陷/未实现范围/人工测试清单 | 本报告 §五＋`todolist.md` B-001 |

**自评结论**：审查准备不完整（受 B-001 限制），正式独立审查应在 Xcode 就绪、D-01/D-02 清零后进行。

## 七、建议的独立审查重点

1. 录音耐久与恢复（§7，发布阻断级）：故障注入测试文件写入失败/数据库提交失败/模型超时/异常退出。
2. 密钥脱敏链路（§5）：从重定向目标、错误文本、调试日志、导出四个出口复核。
3. D-05 的 `@unchecked Sendable` 充分性。
4. 模型适配器契约（§8）：本地模拟服务验证 OpenAI 语音/OpenAI 改写/Anthropic 改写。
5. D-03 菜单栏窗口生命周期与快捷键在主窗口关闭时的行为。
