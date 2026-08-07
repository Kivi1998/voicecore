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

### 2026-08-07 CORE-006 统计服务（Kimi）

- 决策说明：统计只计入已生成最终文字（`final_text` 非空）的记录——输入失败不影响已产出的字数；仓储聚合投影 `started_at`/`count_units` 两字段，趋势按本地时区在服务层分桶，不在 SQL 中做时区换算。
- 决策说明：「本周」固定周一起（`firstWeekday = 2`，`docs/DATA_MODEL.md` §6 口径），今日/本周边界按本地日历取起点后换算 UTC 字符串比较。
- 验证：三包 `swift build` 通过；UnitCounter 8 个测试（CJK 逐字、英文按词、数字成词、标点/空白/Emoji 不计且断词、假名韩文）；StatisticsService 5 个测试（固定 GMT+8＋固定当前时间：跨日、跨周、UTC→本地边界、趋势补零升序、排除无最终文字）；执行待 B-001。

### 2026-08-07 DATA-006 删除编排、导出与存储统计（Kimi）

- 决策说明：删除顺序为先删录音文件（含半成品）再删数据库记录——异常中断后宁可残留“无音频记录”（界面可见可再删），也不产生磁盘上的未知孤儿文件。
- 决策说明：导出格式定为 JSON v1 信封（`HistoryExportEnvelope`，含 formatVersion 便于演进）；只导出脱敏配置快照，不含密钥、鉴权头与任何文件路径；原子写入＋0600 权限。
- 决策说明：数据库文件大小经组合根闭包注入，应用层不感知数据库路径。
- 验证：三包 `swift build` 通过；9 个 XCTest 覆盖删除级联/缺文件/幂等/批量、导出无密钥与路径、原子覆盖无临时残留、存储统计合计；执行待 B-001。

### 2026-08-07 STT-003 重试策略（Kimi）

- 决策说明：自动重试以装饰器实现（`RetryingSpeechProvider`/`RetryingRewriteProvider`），组合根包装具体适配器，流水线与适配器本体无感知；连接测试（用户显式诊断）不做自动重试，需要即时真实错误。
- 决策说明：重试范围严格限定瞬态故障（网络不可用/超时/服务端错误，指数退避 0.5s 起封顶 4s）；限流只自动重试一次；取消与 `isRetryable=false` 直接传播。
- 验证：Providers 包 `swift build` 通过；9 个 XCTest（重试至成功、退避序列、限流一次、不可重试类别、取消不重试、装饰器行为、validate 不重试）；执行待 B-001。

### 2026-08-07 STT-004 / LLM-004 核查与 STT-005 扩展骨架（Kimi）

- 核查结论：STT-004（语音连接测试）随 STT-002 已完整落地——静音 WAV 探针、不产生历史记录、耗时与标准化错误、密钥脱敏、不参与自动重试；LLM-004 随 LLM-002/003 与 CORE-004 已落地——默认中英混合清理提示词（词典优先、防指令注入）、关闭改写直接用原文（端到端测试覆盖）、双适配器连接测试。均满足验收，无新增代码。
- STT-005：新增 `docs/PROVIDER_EXTENSION.md` 扩展指南与两个原生适配器骨架（完整接口＋明确暂不支持错误），组合根可提前登记。
- 验证：Providers 包 `swift build` 通过；2 个骨架 XCTest 已编写；执行待 B-001。

### 2026-08-07 PLAT-003 AVFoundation 录音采集（Kimi）

- 决策说明：采集直接写 `.partial` 半成品（路径解析器由组合根注入，与 FileAudioFileStore 约定一致），停止后经仓储 `finalize` 校验改名——与 DATA-003 的原子落盘设计闭环。
- 决策说明：中断处理采用 AVAudioEngineConfigurationChange 通知：安全停止、已落盘内容保留、上报 `deviceDisconnected`，由编排层决定后续（绝不删除音频）。
- 决策说明：`@preconcurrency import AVFoundation` 隔离 Apple 未标注并发域的实时回调 API；编译零警告。
- 验证：`swift build` 通过；AVAudioEngine 需真实音频环境，运行级验证（出声、电平、拔插设备）待 B-001 解除后在 App 集成测试补做。

### 2026-08-07 PLAT-002 全局快捷键（Kimi）

- 决策说明：采用 Carbon `RegisterEventHotKey` 而非 NSEvent 全局监听——前者不需要辅助功能/输入监听权限且注册即独占，冲突在注册时即可诊断；NSEvent 全局监听需要额外权限且不能独占按键。
- 决策说明：默认快捷键选定 ⌥Space（macOS 14 系统未占用；与输入法切换 ⌃Space 错开），冲突检测为“探测注册＋立即注销”，最终权威是正式注册结果。
- 验证：`swift build` 零警告通过；全局按键接收的运行验证待 B-001。

### 2026-08-07 PLAT-004 / PLAT-006 输入、剪贴板、权限与启动（Kimi）

- 决策说明：自动输入采用剪贴板中转＋`CGEvent` ⌘V（兼容绝大多数输入框），AX 仅用于权限校验与焦点探测；模拟按键事件只含键码不含文字。原剪贴板保存/恢复由编排器（CORE-005）负责，注入器无状态。
- 决策说明：辅助功能权限请求在 `MainActor` 触发系统弹窗（`AXIsProcessTrustedWithOptions`），拒绝后跳系统设置面板；不做轮询。
- 决策说明：单实例守卫放在 Platform 包纯函数，App 入口最早调用；双开激活旧实例并退出。
- 验证：`swift build` 零警告通过；辅助功能授权、⌘V 注入、开机启动注册的运行验证待 B-001。

### 2026-08-07 PLAT-005 菜单栏与录音悬浮条（Kimi）

- 决策说明：菜单栏用 AppKit `NSStatusItem`（动作经 `MenuBarActions` 闭包注入，控制器零业务逻辑）；状态文案集中 `statusText(for:)`，同时供菜单与 VoiceOver。
- 决策说明：悬浮条用 `NSPanel`（borderless＋nonactivatingPanel＋.statusBar 层级），内容经 NSHostingView 桥接 SwiftUI；视觉用系统 `regularMaterial` 而非自制玻璃（UI-006 的 Liquid Glass 升级在应用层按系统版本分支）。
- 附带完成：组合根所需的 `AppPathsService`（`~/Library/Application Support/<bundle-id>/` 五目录，0700 权限）。
- 验证：`swift build` 零警告通过；不抢焦点、VoiceOver 朗读、全空间悬浮的运行验证待 B-001。

### 2026-08-07 PLAT-007 跨平台边界（Kimi）

- 决策说明：四个共享包声明 `iOS(.v16)` 完成“可在移动端编译”的结构前提；保持其不导入 AppKit/SwiftUI/AVFoundation，由 macOS 编译持续约束。
- 决策说明：键盘扩展边界按硬限制写清——扩展不能用麦克风、不发起网络请求、只读 App Group 数据、Deep Link 回主应用；首版不残留任何移动端半成品入口。
- 验证：四包 `swift build` 回归通过。

### 2026-08-07 FND-003 / FND-004 工具链与日志规范（Kimi）

- 决策说明：统一命令入口为仓库根 `Makefile`（DEVELOPMENT.md 要求单入口），Xcode 相关目标经 `check-xcode` 在 CLT 环境明确失败并提示，不产生误导性“成功”。
- 决策说明：严格并发检查采用 swift-tools-version 6.0 的 Swift 6 语言模式（全六包已生效）；SwiftFormat/SwiftLint 版本在配置文件头注释锁定，CI 使用同版本。
- 决策说明：刻意不在 `.env.example` 提供密钥变量——密钥一律走设置页→SQLite→secrets 通道，从机制上防止密钥进入环境变量/日志。
- 验证：`make build-packages`、`make resolve` 实测通过；密钥扫描（git grep）无命中；LogRedactor 6 个 XCTest 已编写；swiftformat/swiftlint 本机未安装，format/lint 实测待工具或 CI。

## G0：工程基线

- [ ] FND-001 初始化 SwiftUI＋AppKit 原生 macOS 项目（进行中；受 B-001 阻塞，Xcode 工程待补）
- [ ] FND-002 建立 App、Features 与 Swift Packages 依赖边界（进行中；六包骨架已建，SwiftPM 解析与编译通过、无循环依赖、Domain 仅依赖 Foundation；Xcode 集成验证待 B-001 解除）
- [ ] FND-003 配置 SwiftFormat、SwiftLint、严格并发检查和统一命令（完成：Makefile 统一入口（resolve/dev/format/format-check/lint/test-packages/build-packages/test-app/e2e/archive，Xcode 目标经 check-xcode 明确报错）；.swiftformat（Swift 6、120 列、LF）；.swiftlint.yml（strict＋自定义 no_secrets_in_logs 错误级规则）；严格并发检查经 swift-tools-version 6.0 的 Swift 6 语言模式全仓生效；已实测 make build-packages 与 make resolve 通过；swiftformat/swiftlint 本机未安装，lint/format 实测待工具安装或 CI）
- [ ] FND-004 建立配置分层与敏感日志规范（完成：docs/CONFIG_AND_LOGGING.md——三层优先级（数据库设置＞开发期环境变量＞代码默认值）、密钥生命周期红线（只存 SQLite、只走 secrets 通道、禁入日志/导出/快照）、日志脱敏规则（LogRedactor 统一、请求日志白名单、剪贴板/口述文字/音频禁入日志）、仓库卫生扫描命令；.env.example 只含非敏感默认值且刻意不提供密钥变量（.env 已在 .gitignore）；LogRedactor 6 个自动测试已编写；git 密钥扫描实测无命中；执行待 B-001）
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
- [ ] CORE-005 实现自动输入与剪贴板恢复编排（代码完成并编译通过：deliver 编排随 CORE-004 落地——restoreClipboard 开启时先快照、注入后恢复、恢复失败仅记诊断不影响已输入、注入失败保留 finalText 且不回滚转录；本轮补 retryInjection 重试入口（仅 injectionFailed、用户显式操作强制注入不受自动输入开关影响）；新增 2 个重试测试；执行待 B-001）
- [ ] DATA-004 实现词典仓储（代码完成并编译通过：DictionaryStore；归一化查重＋唯一索引兜底并发、LIKE 转义搜索、创建时间倒序、allTermStrings 供提示注入；8 个测试已编写；执行待 B-001）
- [ ] DATA-005 实现模型与应用设置仓储（代码完成并编译通过：ProviderProfileStore＋AppSettingsStore；遮罩读取/密钥专用 secrets 通道/更新 nil 保持空串清除/同用途单默认事务切换/被引用配置阻止删除/HTTPS 校验回环例外/设置 JSON 校验；13 个测试已编写；执行待 B-001）
- [ ] STT-002 使用 URLSession 实现 OpenAI 兼容语音转录（代码完成并编译通过：OpenAISpeechProvider multipart 适配器；端点拼接末尾斜杠/完整端点处理、Bearer 鉴权、自定义头合并且保留头禁覆盖、词典 prompt 限长截断、4MB 响应上限、错误按 §10 映射、连接测试内置静音 WAV、URLSessionTransport 超时/取消/脱敏；MockTransport 契约测试 24 个已编写；执行待 B-001）
- [ ] STT-003 实现语音提示、取消、重试和错误归一化（代码完成并编译通过：词典提示注入与限长截断、取消传播已在 STT-002 落地，长音频超时伸缩在 CORE-004 落地；本轮新增 ProviderRetryPolicy＋RetryingSpeechProvider/RetryingRewriteProvider 装饰器——仅网络不可用/超时/服务端错误指数退避自动重试（0.5s 起倍增封顶 4s），限流只重试一次，认证/配置/4xx/格式错误与取消绝不自动重试，连接测试不重试；错误按 16 类标准化可区分；9 个测试已编写；执行待 B-001）
- [ ] STT-004 实现语音模型连接测试（代码完成，随 STT-002 落地并经本轮核查：validate 使用程序生成 0.1 秒静音 WAV 探针、不产生历史记录（不触仓储）、返回耗时 latencyMs 与标准化可理解错误、取消原样传播、密钥经 LogRedactor 不进日志、连接测试不参与自动重试（STT-003 装饰器直通）；MockTransport 契约测试已覆盖；执行待 B-001）
- [ ] LLM-002 使用 URLSession 实现 OpenAI 兼容文字改写（代码完成并编译通过：OpenAIRewriteProvider chat/completions；请求结构、保留头、空文本短路、finish_reason 映射、连接测试；契约测试已编写；执行待 B-001）
- [ ] LLM-003 使用 URLSession 实现 Anthropic 兼容文字改写（代码完成并编译通过：AnthropicRewriteProvider /v1/messages；system 字段、x-api-key、anthropic-version 默认 2023-06-01 可配置、文本块顺序拼接忽略非文本块、无文本块坏响应；契约测试已编写；执行待 B-001）
- [ ] LLM-004 实现默认提示词、关闭改写和连接测试（代码完成，随 LLM-002/003 与 CORE-004 落地并经本轮核查：RewritePromptBuilder 默认中英混合清理提示词（保留事实/数字/代码/专有名词，词典优先按词语边界限长注入，防指令注入）；编排层 rewriteEnabled=false 时原始转录直接成为最终文字（端到端测试已覆盖）；两个改写适配器 validate 使用固定无隐私短文本并返回耗时与标准化错误；执行待 B-001）
- [ ] PLAT-002 使用 AppKit 实现按一次开始、再按一次停止的全局快捷键（代码完成并零警告编译通过：CarbonGlobalShortcut——Carbon RegisterEventHotKey 无需辅助功能权限即可全局可达、注册即独占故系统冲突可发现（eventHotKeyExistsErr 给出可理解错误）、重复注册视为重绑、conflicts 探测注册即注销、事件仅投递异步流不做业务操作、默认 ⌥Space；运行验证待 B-001）
- [ ] PLAT-003 使用 AVFoundation 实现麦克风录音、编码和中断处理（代码完成并零警告编译通过：AVAudioCaptureService——AVAudioEngine tap 实时 AAC 编码边录边写 .partial 半成品、权限检查、指定/默认输入设备（CoreAudio 枚举与 AudioUnit 指派）、RMS 电平 10Hz 限频上报、配置变化安全关闭并报 deviceDisconnected、时长按写入帧数计算、回调线程只做转码写盘、@preconcurrency 隔离 AVFAudio 并发标注；运行与设备实测待 Xcode/真机）
- [ ] PLAT-004 使用 Accessibility API 实现辅助功能权限与自动输入（代码完成并零警告编译通过：AccessibilityTextInjector——AXIsProcessTrusted 权限校验、AX 焦点元素探测、剪贴板中转＋CGEvent ⌘V、按键事件不含文字内容；SystemClipboardService 全类型快照/写文本/读文本/恢复，快照只驻留内存；失败分类 injectionPermissionDenied/injectionTargetUnavailable 且提示文字已保存可复制；运行验证待 B-001）
- [ ] PLAT-005 使用 MenuBarExtra、NSPanel 实现菜单栏和无焦点悬浮条（代码完成并零警告编译通过：StatusItemMenuBarController——NSStatusItem 常驻不依赖主窗口、图标与文案随 15 态更新、动作注入转发、VoiceOver accessibilityLabel 同步状态；RecordingOverlayController——borderless＋nonactivatingPanel 不抢焦点、.statusBar 层级全空间悬浮、SwiftUI 胶囊系统材质 regularMaterial（旧系统自动降级）、电平条同时以文字暴露 VoiceOver、取消按钮、主屏顶部居中；运行验证待 B-001）

## G3：产品页面与完整功能

- [ ] CORE-006 实现中英混合统计和聚合（代码完成并编译通过：UnitCounter CJK 逐字＋拉丁词＋标点空白 Emoji 不计；仓储新增 unitsSummary/unitEntries 聚合（只统计 final_text 非空、投影两字段不全量加载）；StatisticsService 今日/本周（周一起，本地时区边界换算 UTC）/累计/记录条数与 N 日趋势（本地时区分桶＋补零＋升序）；8 个 UnitCounter 测试＋5 个聚合测试（固定 GMT+8 跨日、跨周、时区边界、补零、排除无最终文字）已编写；执行待 B-001）
- [ ] DATA-006 实现删除、导出和存储统计（代码完成并编译通过：RecordLifecycleService 单条/批量删除编排（先删录音含半成品再删库记录级联尝试、缺文件仍完成、幂等、收藏无特殊路径）；HistoryExportService JSON v1 信封（游标分页读取、时间升序、原子写入 0600、脱敏快照不含密钥与任何文件路径）；StorageStatisticsService 录音＋数据库＋条数统计（数据库大小由组合根注入）；仓储补 recordCount；9 个测试已编写；执行待 B-001）
- [ ] STT-005 建立千问、豆包原生适配扩展骨架（代码与文档完成并编译通过：docs/PROVIDER_EXTENSION.md 扩展指南（扩展点总览、七步清单、鉴权/流式/音频格式扩展点、错误映射与取消语义）；QwenSpeechProviderSkeleton/DoubaoSpeechProviderSkeleton 实现完整 SpeechProvider 接口并抛出明确"暂不支持、请用 OpenAI 兼容配置"错误，组合根可提前登记不误导；ProviderProtocolKind 已预留 qwenNative/doubaoNative；2 个骨架测试已编写；执行待 B-001）
- [ ] PLAT-006 实现系统权限引导、SMAppService 开机启动和单实例（代码完成并零警告编译通过：SystemPermissionService 麦克风/辅助功能状态查询与用户触发的请求（拒绝后跳系统设置面板，不静默不轮询）；SMAppLoginItemService 注册/取消/状态；SingleInstanceGuard 双开时激活旧实例并退出，防快捷键冲突与数据库并发写；运行验证待 B-001）
- [ ] PLAT-007 编写 iPhone、iPad 共享包与键盘扩展边界说明（完成：docs/CROSS_PLATFORM.md——四共享包（Domain/Data/Application/Providers）已声明 iOS(.v16) 且保持不导入 AppKit/SwiftUI/AVFoundation，macOS 专有包边界、iOS 主应用复用与重写清单、键盘扩展硬性限制（不能用麦克风、录音只在主应用、App Group 只读、不发起网络请求）；四包 macOS 编译回归通过）
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
