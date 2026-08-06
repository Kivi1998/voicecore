# OpenTypeless 开发任务清单

本文是面向多 Agent、多个 Git worktree 的实施基线。任务 ID 一经开始实施不得重命名；需求变化应新增任务或在原任务下补充验收项。第一版只支持 Apple 芯片 macOS，技术栈固定为 SwiftUI＋AppKit、Swift Package Manager、AVFoundation、URLSession、GRDB＋SQLite；架构为未来 iPhone、iPad 复用核心包预留边界。

## 1. 统一约束

- 无登录、账号、会员、订阅、额度、推荐返佣或云同步。
- 所有录音、历史、词典、配置和 API 密钥保存在本机；密钥暂以明文存入 SQLite。
- 快捷键采用“按一次开始，再按一次结束”；转录成功后默认写入当前输入框。
- 所有成功或失败录音永久保留，只有用户明确删除时才移除。
- 语音识别第一版实现 OpenAI 兼容协议，架构须允许新增千问、豆包原生适配器。
- 文字改写实现 OpenAI 兼容协议和 Anthropic 兼容协议。
- 页面必须遵循根目录 `DESIGN.md`，采用 Apple 原生导航、系统语义颜色、字体、SF Symbols 和控件行为；不得复制第三方品牌、商标、图标或像素级布局。
- 核心业务 Swift Package 不得直接依赖 AppKit 或 macOS 专属 API；平台能力必须通过协议隔离，为未来 iPhone、iPad 的 SwiftUI 主应用与键盘扩展预留边界。
- macOS 26 及以上优先使用系统原生 Liquid Glass；旧系统使用 SwiftUI Material 或 `NSVisualEffectView` 降级，禁止用自绘高光冒充系统玻璃。
- 图标优先使用 SF Symbols，并遵守 Reduce Transparency、Reduce Motion、Increase Contrast 等辅助功能设置。

## 2. 字段说明

- **复杂度**：S（半天内）、M（约 1–2 天）、L（约 3–5 天）、XL（需要拆解与专项验证）。
- **优先级**：P0 阻塞核心闭环；P1 首版必须；P2 首版增强。
- **可并行性**：高表示接口确定后可独立 worktree；中表示需与相邻模块协调；低表示处于关键路径或共享基础文件。
- **分支名**：建议使用 `feat/<任务ID小写>-简述`；同一模块连续任务可在同一模块分支完成，但合并记录必须保留任务 ID。

## 3. 有向依赖与关键路径

```text
FND-001 → FND-002 → FND-003 → CORE-001
CORE-001 → DATA-001、STT-001、LLM-001、PLAT-001
DATA-001 → DATA-002、DATA-005
DATA-001 + PLAT-001 → DATA-003
DATA-002 → CORE-002
CORE-002 + DATA-003 → CORE-003
STT-001 + DATA-005 → STT-002
LLM-001 + DATA-005 → LLM-002
PLAT-001 + DATA-003 → PLAT-003
PLAT-001 → PLAT-004
CORE-002 + STT-002 + LLM-002 + PLAT-003 → CORE-004
CORE-004 + PLAT-004 → CORE-005

CORE-005 + G3 功能完整 → TEST-004 → TEST-005
G3 功能完整 + FND-005 → REL-001 → REL-002
TEST-005 + REL-002 → TEST-006 → REL-003 → REL-004
UI-001 → UI-006 → TEST-007 → G4 发布候选
```

这里不是一条简单的线性关键路径，而是三条前置分支汇入 `CORE-004`：数据分支（`DATA-001 → DATA-005`）、模型分支（`STT-001/LLM-001 → STT-002/LLM-002`）和录音分支（`PLAT-001 → DATA-003 → PLAT-003`）。三者与状态机 `CORE-002` 都完成后才可实现流水线；随后经自动输入、完整功能、真实 Mac 验收、独立审查、干净安装和缺陷回归进入发布。视觉发布支线 `UI-001 → UI-006 → TEST-007` 必须在 G4 前汇合。不得把并列依赖误当成可顺序跳过的任务。

## 4. 阶段门禁

| 门禁 | 必须完成 | 通过条件 |
|---|---|---|
| G0 基线可开发 | FND 全部任务 | 新克隆仓库可解析 Swift Packages、启动原生 macOS 窗口、执行格式化和基础测试 |
| G1 数据与接口冻结 | CORE-001、DATA-001～003、STT-001、LLM-001、PLAT-001 | 公共类型、数据库迁移、平台接口及模型接口经评审，允许并行实现 |
| G2 核心闭环 | CORE-002～005、DATA-004～005、STT-002～004、LLM-002～004、PLAT-002～005 | 真实 Mac 完成“快捷键→录音落盘→转录→改写→输入”且失败可恢复 |
| G3 功能完整 | CORE-006、DATA-006、STT-005、PLAT-006～007、UI、HIST、DICT、SET | 所有首版页面和业务功能满足验收；Liquid Glass 与旧系统降级完成；没有账号/会员残留 |
| G4 发布候选 | TEST-001～005、TEST-007、REL-001～002 | 自动测试通过，权限、辅助功能、崩溃恢复和安装升级在干净 Mac 账户验证通过 |
| G5 正式验收 | TEST-006、REL-003～004 | 缺陷闭环、回归通过、DMG 可安装，文档与制品齐全 |

## 5. 详细任务

### FND：工程基础

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| FND-001 | 初始化原生 Xcode macOS App：SwiftUI 生命周期、AppKit 桥接、macOS 14 最低版本和 Apple Silicon 构建目标 | 无 | M/P0 | 低 | macOS 14 ARM64 原生窗口可启动；无模板业务残留；包名、应用标识和签名设置统一 | `feat/fnd-001-bootstrap` |
| FND-002 | 建立 App、Features 与 Core/Data/Providers/Platform Swift Packages 的产品和依赖边界 | FND-001 | M/P0 | 低 | Xcode 与 SwiftPM 解析通过；Core 不依赖 AppKit；无循环依赖 | `feat/fnd-002-layout` |
| FND-003 | 配置 SwiftFormat、SwiftLint、严格并发检查、统一构建与测试命令 | FND-002 | M/P0 | 低 | 格式、静态检查、Swift 6 并发检查和测试命令在干净环境通过 | `chore/fnd-003-tooling` |
| FND-004 | 建立配置分层、环境变量示例和敏感信息日志规范 | FND-002 | S/P1 | 高 | 仓库无真实密钥；日志脱敏规则有自动测试 | `chore/fnd-004-config` |
| FND-005 | 配置 GitHub CI：Swift Package 测试、Xcode 单元/UI 测试和 ARM64 Archive 冒烟 | FND-003 | M/P1 | 中 | PR 自动检查；固定 Xcode/macOS 版本；失败可定位到明确步骤 | `ci/fnd-005-github-actions` |

### CORE：核心状态机与领域逻辑

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| CORE-001 | 定义口述记录、录音、转录、改写、配置、词典等跨 Apple 平台领域类型 | FND-003 | M/P0 | 低 | 状态枚举覆盖录音中、排队、转录、改写、成功、各类失败和取消 | `feat/core-001-domain` |
| CORE-002 | 实现口述状态机和合法迁移校验 | CORE-001、DATA-002 | L/P0 | 中 | 非法迁移被拒绝；所有状态路径具备单元测试 | `feat/core-002-state-machine` |
| CORE-003 | 实现耐久化作业队列与启动恢复 | CORE-002、DATA-003 | L/P0 | 中 | 强制退出后重启可发现未完成任务；不会重复创建记录 | `feat/core-003-job-recovery` |
| CORE-004 | 编排录音→语音识别→改写→最终文本完整流水线 | CORE-002、STT-002、LLM-002、PLAT-003 | XL/P0 | 低 | 成功与失败均落库；原始文字和最终文字分别保存 | `feat/core-004-pipeline` |
| CORE-005 | 实现自动输入、失败降级到剪贴板和剪贴板恢复编排 | CORE-004、PLAT-004 | L/P0 | 低 | 支持常用输入框；输入失败不丢文本；原剪贴板可恢复 | `feat/core-005-delivery` |
| CORE-006 | 实现中英混合统计规则和日、周、总量聚合服务 | CORE-001、DATA-002 | M/P1 | 高 | 中文按字、英文按词、标点空白不计；跨周与时区测试通过 | `feat/core-006-statistics` |

### DATA：SQLite 与文件持久化

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| DATA-001 | 使用 GRDB 设计 SQLite 表、索引、外键、迁移机制和 UTC 时间规范 | FND-003、CORE-001 | L/P0 | 低 | 空库可迁移；迁移可重复验证；架构覆盖历史、词典、配置和作业 | `feat/data-001-schema` |
| DATA-002 | 实现口述记录仓储及事务边界 | DATA-001 | L/P0 | 中 | 增删改查、状态更新、分页和日期过滤测试通过 | `feat/data-002-record-repo` |
| DATA-003 | 实现录音文件目录、原子写入、路径相对化和文件关联 | DATA-001、PLAT-001 | L/P0 | 中 | 录音先落盘后请求；数据库不保存平台绝对路径；异常无半成品覆盖 | `feat/data-003-audio-store` |
| DATA-004 | 实现词典仓储、唯一约束与搜索 | DATA-001 | S/P1 | 高 | 重复词被阻止；增删查测试通过 | `feat/data-004-dictionary-repo` |
| DATA-005 | 实现模型与应用设置仓储，API 密钥明文存 SQLite | DATA-001 | M/P1 | 高 | 密钥可保存更新；SwiftUI 只取得遮罩展示值；日志不泄露 | `feat/data-005-settings-repo` |
| DATA-006 | 实现单条删除、关联录音删除、数据导出和存储占用统计 | DATA-002、DATA-003 | M/P1 | 中 | 删除需明确确认；收藏无特殊删除保护漏洞；导出默认不含密钥 | `feat/data-006-lifecycle` |

### STT：语音识别适配层

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| STT-001 | 定义语音识别适配器接口、能力声明、统一错误和测试夹具 | CORE-001 | M/P0 | 低 | 文件转录、测试连接、语言、提示词及可扩展流式能力有明确契约 | `feat/stt-001-contract` |
| STT-002 | 使用 URLSession 实现 OpenAI 兼容 `/audio/transcriptions` multipart 适配器 | STT-001、DATA-005 | L/P0 | 高 | 可配置 URL、模型、密钥、语言、自定义头；兼容至少两个服务实现 | `feat/stt-002-openai` |
| STT-003 | 实现词典提示、超时、取消、重试策略和错误归一化 | STT-002、DATA-004 | M/P0 | 中 | 认证、限流、网络、格式错误可区分；取消不触发自动重试 | `feat/stt-003-resilience` |
| STT-004 | 实现连接测试与配置能力探测 | STT-002 | M/P1 | 高 | 不产生历史记录；反馈耗时和可理解错误；密钥不进入日志 | `feat/stt-004-connection-test` |
| STT-005 | 建立千问、豆包原生适配器扩展骨架和协议接入说明，不实现首版原生调用 | STT-001 | M/P2 | 高 | 新增适配器无需修改流水线；文档列清鉴权、流式和音频格式扩展点 | `docs/stt-005-provider-extension` |

### LLM：文字理解与改写

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| LLM-001 | 定义改写适配器接口、提示词输入、统一响应和错误模型 | CORE-001 | M/P0 | 低 | 协议实现可替换；保留原始文本；空文本和取消有明确定义 | `feat/llm-001-contract` |
| LLM-002 | 使用 URLSession 实现 OpenAI 兼容文字改写适配器 | LLM-001、DATA-005 | L/P0 | 高 | URL、模型、密钥、自定义头、温度可配置；响应解析有测试 | `feat/llm-002-openai` |
| LLM-003 | 使用 URLSession 实现 Anthropic 兼容文字改写适配器 | LLM-001、DATA-005 | L/P0 | 高 | 支持标准消息格式和版本头；错误转换与 OpenAI 适配器一致 | `feat/llm-003-anthropic` |
| LLM-004 | 实现默认中英混合清理提示词、关闭改写和连接测试 | LLM-002、LLM-003、DATA-004 | M/P1 | 中 | 不改变事实和专有名词；词典优先；改写关闭时直接使用原始文字 | `feat/llm-004-prompts` |

### PLAT：macOS 平台能力

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| PLAT-001 | 以 Swift protocol 定义录音、快捷键、输入、剪贴板、权限、目录和菜单栏能力 | FND-003、CORE-001 | L/P0 | 低 | Core Package 不导入 AppKit/AVFoundation；协议可由测试替身及未来 iOS 实现 | `feat/plat-001-contracts` |
| PLAT-002 | 使用 AppKit/系统事件能力实现 macOS 全局快捷键：按一次开始、再按一次停止 | PLAT-001 | L/P0 | 高 | 冲突检测、重绑、后台触发、连续快速按键和权限异常均可控 | `feat/plat-002-hotkey` |
| PLAT-003 | 使用 AVFoundation 实现麦克风采集、设备选择、音频编码和中断处理 | PLAT-001、DATA-003 | XL/P0 | 高 | 音频边录边落盘；拔设备、休眠、拒绝权限不会破坏记录 | `feat/plat-003-audio` |
| PLAT-004 | 使用 AppKit 与 Accessibility API 实现辅助功能权限、剪贴板保存恢复及文字注入 | PLAT-001 | XL/P0 | 高 | 常用浏览器、编辑器、办公软件和系统文本框真实验证；权限拒绝有恢复指引 | `feat/plat-004-text-injection` |
| PLAT-005 | 使用 MenuBarExtra、NSPanel/AppKit 桥接实现菜单栏、无焦点悬浮条和状态反馈 | CORE-004、PLAT-002 | L/P1 | 中 | 不抢焦点；支持取消；关闭主窗口后仍工作；VoiceOver 可读状态 | `feat/plat-005-menubar-overlay` |
| PLAT-006 | 实现麦克风/辅助功能权限引导、SMAppService 开机启动、单实例和应用数据目录 | PLAT-001 | L/P1 | 高 | 首次启动引导可恢复；系统设置返回后刷新；重复启动不产生多个录音进程 | `feat/plat-006-lifecycle` |
| PLAT-007 | 预留 iOS/iPadOS SwiftUI 主应用、共享 Swift Packages 与键盘扩展边界说明 | PLAT-001 | M/P2 | 高 | Core/Data/Providers 可在移动端编译；文档说明键盘扩展麦克风和网络限制 | `docs/plat-007-cross-platform` |

### UI：应用框架与首页

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| UI-001 | 按 `DESIGN.md` 建立 SwiftUI Apple 原生设计系统：语义颜色、字体、间距、SF Symbols 和状态规范 | FND-002 | M/P1 | 高 | 使用系统语义值和原生控件层级；符号有可访问标签；支持窗口缩放 | `feat/ui-001-design-system` |
| UI-002 | 使用 NavigationSplitView 构建侧栏、页面壳、标题栏和通用空/载入/错误状态 | UI-001 | L/P1 | 中 | 首页、历史、词典、设置可导航；键盘焦点、VoiceOver 顺序和命令完整 | `feat/ui-002-shell` |
| UI-003 | 实现首页统计卡片、七日趋势、当前模型和最近记录 | UI-002、CORE-006、HIST-001 | L/P1 | 中 | 今日、本周、总量与数据库一致；空数据不出现假数字 | `feat/ui-003-dashboard` |
| UI-004 | 实现通用弹窗、菜单、表单、密钥输入、日期筛选和通知组件 | UI-001 | L/P1 | 高 | 键盘可操作；危险操作二次确认；密钥默认遮罩 | `feat/ui-004-components` |
| UI-005 | 实现中文文案资源、日期时间本地化及英文扩展结构 | UI-002 | M/P2 | 高 | 页面无散落硬编码；中英文长度变化不破版 | `feat/ui-005-i18n` |
| UI-006 | 实现原生 Liquid Glass 与旧系统材质降级，并响应 Reduce Transparency、Reduce Motion、Increase Contrast | UI-001、PLAT-005 | L/P1 | 中 | macOS 26 使用系统玻璃 API；旧系统稳定降级；减少透明度时可读、减少动态时无强制动画 | `feat/ui-006-liquid-glass-accessibility` |

### HIST：历史记录

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| HIST-001 | 实现历史查询服务：分页、日期范围、状态、收藏和全文搜索 | DATA-002 | L/P1 | 高 | 任意日期可查；大量记录分页稳定；组合筛选正确 | `feat/hist-001-query` |
| HIST-002 | 实现按日期分组的历史列表与详情展开 | HIST-001、UI-002、UI-004 | L/P1 | 中 | 显示时间、时长、状态、原始/最终文本及模型信息 | `feat/hist-002-list` |
| HIST-003 | 实现复制、下载、收藏、删除操作 | HIST-002、DATA-006 | M/P1 | 中 | 操作即时反馈；下载文件可播放；删除同步清理数据库与录音 | `feat/hist-003-actions` |
| HIST-004 | 实现失败提示、重新转录和仅重新改写 | HIST-002、CORE-003、CORE-004 | L/P1 | 中 | 失败录音可重试；改写失败不重复上传音频；保留失败原因 | `feat/hist-004-retry` |
| HIST-005 | 实现历史页面大数据量性能与滚动位置保持 | HIST-002 | M/P2 | 高 | 预设大数据集滚动流畅；返回详情后位置不丢失 | `perf/hist-005-list` |

### DICT：个人词典

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| DICT-001 | 实现单词增删查服务和输入规范化 | DATA-004 | S/P1 | 高 | 只允许单条添加；空白、重复和超长输入有提示 | `feat/dict-001-service` |
| DICT-002 | 实现词典列表、搜索、添加弹窗和删除交互 | DICT-001、UI-002、UI-004 | M/P1 | 高 | 新词立即显示；键盘提交有效；删除可确认 | `feat/dict-002-page` |
| DICT-003 | 将启用词典注入语音提示和改写提示 | DICT-001、STT-003、LLM-004 | M/P1 | 中 | 专有名词在模拟请求中出现；长度超限有稳定截断策略 | `feat/dict-003-prompt-integration` |

### SET：设置与模型管理

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| SET-001 | 实现应用设置服务和默认值：快捷键、麦克风、自动输入、启动项 | DATA-005、PLAT-001 | M/P1 | 高 | 设置重启后保持；默认值与首版约束一致 | `feat/set-001-app-settings` |
| SET-002 | 实现语音模型配置页，首版 OpenAI 兼容并展示千问/豆包扩展说明 | SET-001、STT-004、UI-004 | L/P1 | 高 | 可新增、编辑、启用、测试；密钥编辑不误清空原值 | `feat/set-002-stt-settings` |
| SET-003 | 实现 OpenAI/Anthropic 改写模型配置页和提示词设置 | SET-001、LLM-004、UI-004 | L/P1 | 高 | 两种协议可切换、测试、启用；关闭改写可正常工作 | `feat/set-003-llm-settings` |
| SET-004 | 实现录音永久保留说明、空间统计、打开数据目录、手动清理和导出入口 | SET-001、DATA-006 | M/P1 | 中 | 不存在自动清理；用户明确选择范围并二次确认后才可清理；导出提示密钥策略 | `feat/set-004-storage-settings` |

### TEST：审查、测试与缺陷闭环

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| TEST-001 | 建立 Swift Package 核心、GRDB 仓储、URLSession 适配器的 XCTest/Swift Testing 矩阵 | G1 | L/P0 | 高 | 关键领域分支和错误路径均有测试；无真实付费 API 依赖 | `test/test-001-backend` |
| TEST-002 | 建立 SwiftUI 视图模型、快照及 XCUITest 页面测试 | UI-002 | L/P1 | 高 | 关键交互、空态、错误态、删除确认、密钥遮罩和键盘导航有测试 | `test/test-002-frontend` |
| TEST-003 | 建立模型协议契约测试和可重复的模拟服务器 | STT-004、LLM-004 | L/P0 | 高 | OpenAI/Anthropic 正常、限流、超时、畸形响应均可复现 | `test/test-003-provider-contract` |
| TEST-004 | 在真实 Apple Silicon Mac 执行端到端功能验收 | G3 | XL/P0 | 低 | 快捷键、权限、录音、转录、改写、输入、历史、重试全部通过 | `test/test-004-macos-e2e` |
| TEST-005 | 进行完整代码审查、安全与隐私检查、性能检查并登记缺陷 | TEST-001～004、TEST-007 | L/P0 | 低 | 每个问题有严重级别、复现步骤、责任模块和修复任务 | `review/test-005-audit` |
| TEST-006 | 完成缺陷修复、回归验证和发布阻断问题清零 | TEST-005、REL-002 | XL/P0 | 低 | P0/P1 缺陷为零；P2 有明确结论；全量回归报告通过 | `fix/test-006-regression` |
| TEST-007 | 执行视觉与辅助功能矩阵：Liquid Glass、材质降级、VoiceOver、键盘、对比度、减少透明度/动态 | UI-006、PLAT-005 | L/P0 | 低 | 覆盖 macOS 26 与最低支持版本；无不可读玻璃、眩晕动画或仅靠颜色表达状态 | `test/test-007-visual-accessibility` |

### REL：打包、发布与交付

| ID | 目标与输出 | 依赖 | 复杂度/优先级 | 可并行性 | 验收标准 | 建议分支名 |
|---|---|---|---|---|---|---|
| REL-001 | 配置 ARM64 `.app`、图标、权限声明、版本和 DMG 构建 | G3、FND-005 | L/P0 | 中 | Release 构建无调试资源；应用标识和权限文案正确 | `build/rel-001-macos-bundle` |
| REL-002 | 在全新 macOS 用户账户验证 DMG 安装、首次权限、运行和卸载 | REL-001、TEST-004 | L/P0 | 低 | 不依赖开发环境；首次使用闭环成功；卸载说明准确 | `test/rel-002-clean-install` |
| REL-003 | 完成最终 README、用户手册、故障排查、数据位置和开发说明 | TEST-006 | M/P1 | 高 | 新用户按文档可安装；新开发者可构建；安全限制明确 | `docs/rel-003-documentation` |
| REL-004 | 生成校验值、发布说明、已知问题和最终验收记录 | REL-002、REL-003 | M/P1 | 低 | 制品、版本、提交、校验值一一对应；验收人签字确认 | `release/rel-004-final` |

## 6. 合并规则

1. 每个 PR 标题必须包含任务 ID；一个 PR 可覆盖多个紧密相关 ID，但不得横跨无关模块。
2. 公共契约文件由对应基础任务分支独占；其他 worktree 只能消费，不得并行修改。
3. 数据库迁移只允许追加，已合并迁移不得改写。
4. Agent 开工前必须确认依赖任务已合并到集成分支；不能以本地未合并提交作为隐式依赖。
5. 每个功能 PR 必须包含相应测试或说明为何测试由后续固定任务承担。
6. 合并顺序服从依赖图；门禁未通过不得进入下一阶段的集成验收。
