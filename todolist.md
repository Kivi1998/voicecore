# OpenTypeless 可执行待办

本文件与 `tasklist.md` 的任务 ID 一一对应。勾选表示代码、测试、文档和该任务验收标准全部完成并已合并；仅“代码写完”不得勾选。

## 执行记录（按时间追加）

### 2026-08-07 Kimi 开工

- 已完整阅读 `KIMI_PROMPT.md`、`README.md`、`DESIGN.md`、`tasklist.md`、`todolist.md` 及 `docs/` 全部文档。
- 当前为单 Agent 顺序开发（WORKTREE_GUIDE 第 0 波本就要求单线程），采用任务粒度提交，提交信息携带任务 ID；暂不创建多 worktree。
- 负责人/代理：Kimi；集成分支：`main`。

## 阻塞项

### B-001 开发机未安装完整 Xcode（2026-08-07 记录）

- 现象（可复现）：`xcodebuild -version` 报错 `active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`；`/Applications/` 下无 Xcode.app；`xcrun --find xcodebuild` 失败。
- 影响：FND-001 验收（原生窗口启动）、FND-003 部分统一命令、FND-005 CI 的 Xcode 测试/Archive、全部 `xcodebuild` 构建、XCUITest、`.app`/`.dmg` 交付均无法在本机验证。已实测：CLT 不含 `Testing` 与 `XCTest` 模块（`swift test` 报 `no such module`），因此**任何测试都无法在本机执行**，只能做 `swift build` 编译验证。
- 不受影响：Swift 6.3.3 工具链与 CLT（SDK macOS 26）可用，`swift build` 可正常编译纯 Swift Package；第三方依赖（GRDB）网络可达（已实测 git ls-remote 成功）。
- 测试框架决策：仓库统一使用 XCTest（兼容 CLT/Xcode 与最低系统要求；Swift Testing 在 CLT 不可用）。在 Xcode 安装前，测试代码照常编写，但任务完成勾选以“编译通过＋测试代码就绪”为 interim 状态，安装 Xcode 后统一补跑全部测试再正式勾选。
- 对策：先用 SwiftPM 推进可验证的业务核心包开发（FND-002 包边界、CORE/DATA/STT/LLM 契约与实现），并搭好 Xcode 工程目录结构；FND-001 的 Xcode 工程与签名设置等待用户安装 Xcode 后补建并验证，不伪造“窗口可启动”的完成状态。
- 需要用户操作：安装完整 Xcode（App Store 或 Apple Developer 下载），安装后执行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。

### 2026-08-07 CORE-001 领域类型（Kimi）

- 决策说明：`queued` 状态为 KIMI_PROMPT §2.1 与 tasklist CORE-001 验收要求、超出 DATA_MODEL §3.1 列表的补充值，语义为“已排队等待进入处理阶段”，无实质文档冲突，已在代码注释记录。
- 决策说明：错误类别实为 16 个（DATA_MODEL §3.4 列表），状态 15 个。
- 验证：`swift build` 六包全部通过；XCTest 测试 6 个文件已编写，执行待 B-001 解除。

### 2026-08-07 DATA-001 数据库架构（Kimi）

- 新依赖登记：GRDB 7.11.1（https://github.com/groue/GRDB.swift，MIT 许可证），用途为 SQLite 访问/事务/迁移（D-017 已确认技术选型），`Package.resolved` 已提交锁定。
- 决策说明：`provider_profiles.timeout_seconds` 列来自 KIMI_PROMPT §2.5“模型配置至少包括…超时”的要求，专项数据文档未列出，按优先级规则补充并注释。
- 决策说明：记录表对配置的外键采用 `ON DELETE SET NULL` 兜底；删除被引用配置的阻止逻辑由 DATA-005 仓储实现。
- 验证：六包 `swift build` 全部通过；迁移、外键、唯一索引、级联删除、文件权限、UTC 编码共 8 个 XCTest 已编写，执行待 B-001 解除。

### 2026-08-07 DATA-002 记录仓储（Kimi）

- 决策说明：仓储协议（DictationRecordRepository 等）定义在 Domain 包而非 Application 包，保持 Data 仅依赖 Domain；Application 层直接消费协议。与 ARCHITECTURE §7 推荐依赖图的差异在此记录。
- 决策说明：历史分页采用 `(started_at, id)` 双键降序游标，禁止全量加载；搜索使用参数化 LIKE 并转义通配符（FTS5 按数据文档达到性能阈值后再迁移）。

### 2026-08-07 CORE-004 流水线编排（Kimi）

- 决策说明：编排器放在 Application 包并定义为 actor，作为唯一推进状态机的模块；`DictationRecordRepository` 补充 `saveAttempt`（完成时写回成功/耗时/请求标识/错误），协议与实现同步变更。
- 决策说明：转录超时按音频时长伸缩（60 秒＋每 2 秒音频加 1 秒，封顶 600 秒），对应 STT-003 的长音频要求，编排层先落地，适配器层复用。
- 附带完成：CORE-006 的 `UnitCounter`（CJK 逐字＋拉丁词计数）随最终文字保存一并落地。
- 验证：六包 `swift build` 全部通过；9 个端到端 XCTest（真 GRDB 临时库＋真 FileAudioFileStore＋内存替身）覆盖全流程成功、关改写、关自动输入、转录/改写/注入失败保留与重试、重复开始拒绝、取消、未配置拒绝；执行待 B-001。

### 2026-08-07 CORE-003 作业队列与启动恢复（Kimi）

- 决策说明：首版以口述记录状态机本身作为耐久化作业队列——每条非终态记录即一个可恢复作业，`findIncomplete` 重启全量可发现，从机制上保证“不会重复创建记录”，故不引入独立 jobs 表（避免双写不一致）。
- 决策说明：状态机迁移表补充 `.queued → audioSaved/recordingFailed` 启动恢复转移；恢复转移全部经状态机校验。
- 决策说明：恢复出的中断记录统一标记 `appInterrupted` 错误类别；`ready`/`injecting` 恢复为 `injectionFailed`，绝不自动向未知焦点重复输入（服务不持有注入器）。
- 验证：六包 `swift build` 通过；10 个 XCTest 覆盖正式文件恢复、半成品收养、缺失标记、三个网络/输入阶段转移、终态不动、幂等与不新建记录；执行待 B-001。

## G0：工程基线

- [ ] FND-001 初始化 SwiftUI＋AppKit 原生 macOS 项目（进行中；受 B-001 阻塞，Xcode 工程待补）
- [ ] FND-002 建立 App、Features 与 Swift Packages 依赖边界（进行中；六包骨架已建，SwiftPM 解析与编译通过、无循环依赖、Domain 仅依赖 Foundation；Xcode 集成验证待 B-001 解除）
- [ ] FND-003 配置 SwiftFormat、SwiftLint、严格并发检查和统一命令
- [ ] FND-004 建立配置分层与敏感日志规范
- [ ] FND-005 配置 Swift/Xcode CI 和 ARM64 Archive 冒烟

## G1：接口和数据结构冻结

- [ ] CORE-001 定义跨 Apple 平台领域类型（代码完成并编译通过：DictationStatus 15 态含 queued、ErrorCategory 16 类、ProviderProtocolKind 5 协议、DictationRecord/RecordAttempt/ProviderProfile/快照/DictionaryTerm；XCTest 6 个测试文件就绪；测试执行待 B-001 解除）
- [ ] DATA-001 使用 GRDB 设计 SQLite 架构、索引和迁移（代码完成并编译通过：GRDB 7.11.1 精确锁定（MIT）、v0001_initial 五表＋索引＋外键、WAL/busy timeout/0700/0600 权限、UTC RFC3339 编码、迁移清单快照测试与级联删除等 8 个测试已编写；执行待 B-001）
- [ ] DATA-002 实现口述记录仓储（代码完成并编译通过：DictationRecordStore 实现 Domain 仓储协议；状态更新同事务清/写错误、双键游标稳定分页、日期/状态/收藏/搜索组合筛选、LIKE 转义、findIncomplete 恢复扫描、尝试记录增查计数、删除级联；13 个测试已编写；执行待 B-001）
- [ ] DATA-003 实现录音文件持久化（代码完成并编译通过：AudioFileStore 协议＋FileAudioFileStore；.partial 半成品原子落盘、finalize 校验改名与崩溃收养、目录穿越抛错不崩溃、UUID 日期分目录、删除同步清半成品、占用统计含半成品；10 个测试已编写；执行待 B-001）
- [ ] STT-001 定义语音识别适配器契约（代码完成：SpeechProvider 协议、SpeechCapabilities 能力声明、SpeechRequest/SpeechResult、ValidationResult、标准化错误沿用 ErrorCategory；替身契约测试已编写；执行待 B-001）
- [ ] LLM-001 定义文字改写适配器契约（代码完成：RewriteProvider 协议、RewriteCapabilities、RewriteRequest/RewriteResult/FinishReason、空文本与取消语义已在文档注释固定；替身契约测试已编写；执行待 B-001）
- [ ] PLAT-001 定义跨平台能力接口（代码完成并编译通过：AudioCapture/GlobalShortcut/TextInjector/ClipboardService/PermissionService/AutostartService/MenuBarService/PathService＋RecordingRelativePath 纯函数校验；Domain 未导入 AppKit/AVFoundation；测试替身可实现的契约测试已编写；执行待 B-001）

## G2：核心口述闭环

- [ ] CORE-002 实现口述状态机和合法迁移校验（代码完成并编译通过：DictationStateMachine 合法迁移表唯一权威；主路径、各阶段失败重试、取消、启动恢复转移齐全；测试含 15×15 全枚举矩阵拒绝非法迁移与自迁移；执行待 B-001）
- [ ] CORE-003 实现耐久化作业队列和启动恢复（代码完成并编译通过：以口述记录状态机本身作为耐久队列，重启经 findIncomplete 全部可发现、机制上不会重复创建记录，不引入独立作业表；StartupRecoveryService 按 ARCHITECTURE §5.1 恢复：录音阶段校验正式文件/收养 .partial 半成品/标记 recordingFailed，transcribing→transcriptionFailed、transcribed/rewriting→rewriteFailed、ready/injecting→injectionFailed（绝不自动重复输入），错误类别 appInterrupted；状态机补 queued 恢复转移；单条失败不中断扫描、幂等；10 个测试已编写；执行待 B-001）
- [ ] CORE-004 编排录音、转录和改写流水线（代码完成并编译通过：DictationOrchestrator actor 唯一推进状态机；单活跃会话、先建库再采集、停录后关文件校验→转录→可选改写→自动输入、各阶段失败分类落库且不回滚后续成果、尝试记录经 saveAttempt 完整写回、retryTranscription/retryRewrite 重试入口、PipelineContracts 选项/工厂/事件流；9 个端到端测试用真 GRDB 临时库＋真文件仓储＋内存替身已编写；执行待 B-001）
- [ ] CORE-005 实现自动输入与剪贴板恢复编排
- [ ] DATA-004 实现词典仓储（代码完成并编译通过：DictionaryStore；归一化查重＋唯一索引兜底并发、LIKE 转义搜索、创建时间倒序、allTermStrings 供提示注入；8 个测试已编写；执行待 B-001）
- [ ] DATA-005 实现模型与应用设置仓储（代码完成并编译通过：ProviderProfileStore＋AppSettingsStore；遮罩读取/密钥专用 secrets 通道/更新 nil 保持空串清除/同用途单默认事务切换/被引用配置阻止删除/HTTPS 校验回环例外/设置 JSON 校验；13 个测试已编写；执行待 B-001）
- [ ] STT-002 使用 URLSession 实现 OpenAI 兼容语音转录（代码完成并编译通过：OpenAISpeechProvider multipart 适配器；端点拼接末尾斜杠/完整端点处理、Bearer 鉴权、自定义头合并且保留头禁覆盖、词典 prompt 限长截断、4MB 响应上限、错误按 §10 映射、连接测试内置静音 WAV、URLSessionTransport 超时/取消/脱敏；MockTransport 契约测试 24 个已编写；执行待 B-001）
- [ ] STT-003 实现语音提示、取消、重试和错误归一化
- [ ] STT-004 实现语音模型连接测试
- [ ] LLM-002 使用 URLSession 实现 OpenAI 兼容文字改写（代码完成并编译通过：OpenAIRewriteProvider chat/completions；请求结构、保留头、空文本短路、finish_reason 映射、连接测试；契约测试已编写；执行待 B-001）
- [ ] LLM-003 使用 URLSession 实现 Anthropic 兼容文字改写（代码完成并编译通过：AnthropicRewriteProvider /v1/messages；system 字段、x-api-key、anthropic-version 默认 2023-06-01 可配置、文本块顺序拼接忽略非文本块、无文本块坏响应；契约测试已编写；执行待 B-001）
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
