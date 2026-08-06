# OpenTypeless 架构设计

## 1. 架构目标

OpenTypeless 第一版是仅支持 Apple Silicon macOS 的本地语音输入应用。用户按一次全局快捷键开始录音，再按一次结束；应用将录音永久保存到本机，调用语音识别和文字改写服务，并将最终文字自动写入当前获得焦点的输入框。

首版不包含登录、会员、订阅、云同步或自建服务端。所有历史记录、设置、词典、模型配置和 API 密钥均保存在本机 SQLite；API 密钥暂按明文保存，安全加固属于后续版本。

架构必须同时满足：

- 任何网络错误都不能导致录音丢失。
- 页面、业务流程、模型协议和 macOS 系统能力彼此解耦。
- 第一版可以快速交付，同时让未来 iPhone、iPad 复用 SwiftUI、领域、数据和模型适配层。
- 同一个核心流程可替换语音识别和文字改写供应商。
- 所有状态变化可追踪、可恢复、可测试。

## 2. 技术栈

| 层级 | 技术 | 责任 |
|---|---|---|
| 应用与界面 | SwiftUI | 首页、历史、词典、设置、录音状态浮层；未来与 iPhone、iPad 共享 |
| macOS 集成 | AppKit | 窗口、菜单栏、全局快捷键、辅助功能、剪贴板和应用生命周期 |
| 状态观察 | Observation / Combine | 将应用服务状态映射为 SwiftUI 可观察模型，不作为持久化真相来源 |
| 音频 | AVFoundation | 麦克风权限、设备、采集、编码、播放和音频会话 |
| 网络 | URLSession | HTTP、上传、取消、超时；按需使用 `URLSessionWebSocketTask` |
| 数据库 | GRDB + SQLite | 记录、词典、配置、设置、事务和版本化迁移 |
| 模块化 | Swift Package Manager | 领域、数据、模型适配和平台模块的边界与依赖管理 |
| 测试 | XCTest / Swift Testing | 单元、集成、协议契约和数据库迁移测试 |

具体依赖版本在实现时锁定，禁止仅使用宽泛的主版本范围。新增依赖必须说明用途、许可证和替代方案。

## 3. 总体分层

```text
SwiftUI 展示层
    │ @Observable / AsyncStream / async 方法
应用服务层（Swift Package）
    ├── 口述会话编排
    ├── 历史、统计、词典、设置
    └── 重试与恢复
领域核心层
    ├── 状态机和领域实体
    ├── 语音识别统一接口
    └── 文字改写统一接口
基础设施层（Swift Package）
    ├── SQLite 仓储
    ├── 录音文件仓储
    ├── HTTP / WebSocket 客户端
    └── 结构化日志
平台能力层
    ├── macOS 快捷键
    ├── macOS 麦克风权限
    ├── macOS 辅助功能与文字注入
    ├── 剪贴板、菜单栏、自动启动
    └── 未来 iOS / iPadOS 实现
```

依赖方向只能由外向内。领域核心不得导入 SwiftUI、AppKit、AVFoundation、GRDB 或具体供应商实现；只依赖 Foundation 和自身协议。SwiftUI 视图不得直接执行 SQL、文件操作或供应商鉴权。

## 4. 核心模块及边界

### 4.1 SwiftUI 应用界面

SwiftUI 层只负责展示状态、接收用户操作、进行表单级验证，并调用应用服务。它不能自行决定口述会话状态，也不能直接持久化关键业务数据。页面状态模型运行于 `@MainActor`，长时任务在应用服务的结构化并发任务中执行。

页面包括：

- 首页：今日、本周、总口述量，口述次数、时长、最近记录和当前模型。
- 历史记录：日期范围、状态、收藏和全文搜索；复制、下载、重试、重新改写、收藏、删除。
- 词典：添加单个词语、搜索、删除、重复检查。
- 设置：快捷键、麦克风、语音服务、改写服务、自动输入、声音、启动项、数据目录和存储占用。
- 录音浮层：空闲时隐藏；录音、处理中、成功和失败时显示极少信息。

界面必须遵循根目录 `DESIGN.md`：使用 Apple 系统语义字体、颜色、SF Symbols、原生导航和标准控件。在系统支持时通过 SwiftUI/AppKit 原生 API 使用 Liquid Glass；旧系统使用原生 Material 或视觉效果降级。玻璃只属于导航、工具栏、录音胶囊和临时浮层，不覆盖长文本与数据内容层。

### 4.2 口述会话编排器

这是唯一可以推进口述状态机的模块。职责包括：

1. 接收快捷键事件并进行防抖。
2. 开始录音前创建数据库记录和录音目标文件。
3. 将音频持续写盘，而非只保存在内存。
4. 停止录音后安全关闭文件，再调用语音识别。
5. 保存原始转录后调用文字改写；关闭改写时直接采用原始转录。
6. 保存最终文字后调用平台文字输入器。
7. 每一步均持久化状态、错误类别和时间。
8. 通过 `AsyncStream` 或主线程可观察状态向界面发布不可变状态事件。

同一时刻最多允许一个活跃录音会话。新的开始请求若遇到活跃会话，应返回明确的“已有录音进行中”，不能静默覆盖。

### 4.3 音频模块

职责包括麦克风枚举、设备选择、采样格式协商、音频采集、编码、文件完整性检查和时长计算。

macOS 实现以 `AVAudioEngine` 输入节点采集音频，使用 `AVAudioFile` 持续写入；权限通过 `AVCaptureDevice` 查询和申请。录音模块向领域层暴露异步事件流，不把 `AVAudioPCMBuffer`、设备对象或 AVFoundation 错误类型泄漏到领域层。录音回调线程只完成有界缓冲和写盘调度，不能执行数据库或网络操作。

基本要求：

- 开始网络请求前必须已经生成可独立播放的本地录音。
- 成功、失败、收藏与否均永久保存录音，除非用户明确删除。
- 目标格式优先选择兼顾兼容性与容量的单声道压缩格式；若供应商只接受特定格式，在临时目录转码，原始长期文件不被覆盖。
- 录音文件使用 UUID 命名，按年月日分目录，不使用用户口述内容命名。
- 数据库只保存相对录音根目录的路径，避免绑定 macOS 绝对路径。
- 检测设备断开、无采样数据、文件写入失败和时长过短。

### 4.4 语音识别模块

通过统一 `SpeechProvider` 接口隔离供应商。OpenAI 音频转录协议是首版必做；千问和豆包通过独立适配器或预设扩展，详见 `PROVIDER_PROTOCOLS.md`。

模块只返回标准结果：原始文字、可选语言、可选时长、供应商请求标识及用量元数据。供应商私有响应不得传播到领域层。

### 4.5 文字改写模块

通过统一 `RewriteProvider` 接口支持 OpenAI 兼容协议和 Anthropic 协议。输入包括原始文字、词典、语言提示和用户提示词；输出仅包含最终文字及标准元数据。

改写失败不能把整条记录标记为“转录失败”。此时原始文字仍可复制、自动输入或再次改写。

### 4.6 文字输入器

领域层只调用 `TextInjector.insert(text)`。macOS 实现负责：

- 检查辅助功能权限。
- 尽可能记录当前剪贴板内容。
- 将最终文字写入剪贴板并模拟粘贴。
- 在可靠的延迟后尝试恢复原剪贴板。
- 将“文字已生成但输入失败”作为独立错误，不回滚转录结果。

macOS 实现使用 AppKit 剪贴板与 Core Graphics 辅助功能事件完成粘贴；全局快捷键优先使用系统事件监听或经过审查的轻量实现。辅助功能信任状态通过系统 API 检查，权限提示必须由用户操作触发。AppKit 对象和回调保持在主线程或其文档要求的队列中。

密码框、安全输入框或禁止辅助功能的应用可能无法写入。此类失败必须保留最终文字并提供一键复制。

### 4.7 数据与文件仓储

SQLite 是结构化数据的唯一真相来源；录音文件系统是音频内容来源。仓储层通过 GRDB 提供事务边界，禁止 SwiftUI 视图执行 SQL。数据库结构和迁移规则见 `DATA_MODEL.md`。

### 4.8 统计模块

统计基于成功产生的最终文字；如果改写关闭，则最终文字等于原始文字。计数规则：每个中文、日文或韩文字形计一个单位；连续英文、数字词计一个单位；空白和纯标点不计。日期按用户当前本地时区分组，数据库时间统一保存 UTC。

统计模块输出今日、本周和总量，不把展示格式写入数据库。周起始日首版为星期一，未来可配置。

## 5. 口述状态机

```text
CREATED
  └── RECORDING
        ├── CANCELLED
        ├── RECORDING_FAILED
        └── AUDIO_SAVED
              └── TRANSCRIBING
                    ├── TRANSCRIPTION_FAILED
                    └── TRANSCRIBED
                          ├── READY（关闭改写）
                          └── REWRITING
                                ├── REWRITE_FAILED
                                └── READY
                                      └── INJECTING
                                            ├── INJECTION_FAILED
                                            └── COMPLETED
```

状态含义：

- `CREATED`：记录已创建，尚未获得音频帧。
- `RECORDING`：正在采集并持续写盘。
- `AUDIO_SAVED`：文件已安全关闭且通过基本完整性检查。
- `TRANSCRIBING`：正在调用语音服务。
- `TRANSCRIBED`：原始文字已落库。
- `REWRITING`：正在调用改写服务。
- `READY`：最终文字已落库，等待自动输入。
- `INJECTING`：正在向当前输入框写入。
- `COMPLETED`：文字已成功写入。
- `*_FAILED`：对应阶段失败，可按能力恢复。
- `CANCELLED`：用户主动取消；是否保留极短录音由产品规则确定，默认保留并允许删除。

仅允许预定义转移。每次状态变化与关联字段更新必须处于同一数据库事务中。

### 5.1 恢复规则

| 启动时状态 | 恢复动作 |
|---|---|
| `CREATED` / `RECORDING` | 检查录音文件；存在有效音频则转为 `AUDIO_SAVED`，否则 `RECORDING_FAILED` |
| `TRANSCRIBING` | 转为 `TRANSCRIPTION_FAILED`，错误类别为应用异常中断，可重试 |
| `TRANSCRIBED` / `REWRITING` | 若原始文字存在，转为 `REWRITE_FAILED`，可仅重新改写 |
| `READY` / `INJECTING` | 不自动向未知焦点重复输入；转为 `INJECTION_FAILED`，提示复制或手动再次输入 |
| 终态 | 不处理 |

重试转录使用原录音并保留之前的失败信息。重试改写不得再次调用语音服务。任何自动恢复都不得在应用启动时突然向其他应用输入文字。

## 6. 平台抽象与未来 Apple 平台扩展

定义以下平台接口：

- `AudioCapture`：设备枚举、开始、停止、取消。
- `GlobalShortcut`：注册、注销和冲突检测。
- `TextInjector`：向当前输入目标写入文字。
- `ClipboardService`：读取、写入和恢复。
- `PermissionService`：麦克风、辅助功能等权限状态。
- `AutostartService`：登录启动。
- `MenuBarService`：菜单栏菜单和状态。
- `PathService`：数据、缓存和日志目录。

iPhone 和 iPad 可直接复用 SwiftUI 设计系统、领域实体、状态机、GRDB 仓储、统计、词典以及 URLSession 模型适配器。AVFoundation 录音接口也能共享大部分实现，但必须分别处理 macOS 与 iOS 音频会话和权限细节。

iPhone 和 iPad 没有桌面全局快捷键，第三方键盘扩展也不能直接使用麦克风，因此移动端仍属于独立产品入口。未来需要主应用、键盘扩展、App Group 数据交换、Deep Link 返回和移动端交互设计。键盘扩展只负责把已生成文字插入当前输入框；录音必须由主应用执行。首版不得为移动端提前引入复杂流程。

Apple 原生栈不再以 Windows 为复用目标。未来若决定支持 Windows，可以复用协议和数据库规范，但 SwiftUI、AppKit、AVFoundation 及大部分 Swift 实现不能直接运行，需另立客户端项目。

## 7. 推荐目录结构

```text
opentypeless/
├── OpenTypeless.xcodeproj
├── App/
│   ├── OpenTypelessApp.swift
│   ├── AppDelegate.swift
│   ├── Features/
│   │   ├── Dashboard/
│   │   ├── History/
│   │   ├── Dictionary/
│   │   ├── Settings/
│   │   └── RecordingOverlay/
│   ├── DesignSystem/
│   ├── Resources/
│   └── macOS/
│       ├── Windowing/
│       ├── MenuBar/
│       ├── Shortcuts/
│       ├── Accessibility/
│       └── Clipboard/
├── Packages/
│   ├── OpenTypelessDomain/
│   ├── OpenTypelessApplication/
│   ├── OpenTypelessData/
│   ├── OpenTypelessAudio/
│   ├── OpenTypelessProviders/
│   └── OpenTypelessPlatform/
├── Tests/
│   ├── Fixtures/
│   └── SystemTests/
├── docs/
└── scripts/
```

每个 `Packages/*` 是独立 Swift Package target 或清晰 target。功能界面按 Feature 组织，公共视觉组件进入 DesignSystem。禁止创建一个同时处理快捷键、录音、网络、数据库和输入注入的巨大 AppModel。

推荐依赖图：

```text
OpenTypelessDomain          仅依赖 Foundation
        ↑
OpenTypelessApplication     依赖 Domain 中的实体与服务协议
   ↑          ↑          ↑          ↑
Data       Audio      Providers   Platform    各自实现 Application/Domain 协议
   \          |          |          /
             macOS App                       唯一组合根；SwiftUI/AppKit 界面
```

App target 是唯一组合根，负责构造 GRDB 数据库、URLSession、AVFoundation 录音器、AppKit 平台服务和应用服务。各 Package 禁止使用全局单例偷偷绕过依赖边界。

## 8. 并发和事件规则

- 应用服务中的状态机 Actor 为唯一写入者；界面观察可能延迟，重新进入页面后必须通过仓储查询恢复真实状态。
- 快捷键事件进入同一个 Actor 串行处理，并做防抖。
- 网络调用使用 Swift 结构化并发，但同一记录同一阶段只能有一个有效 `Task`。
- 重试操作需要乐观并发检查，防止用户连续点击产生重复请求。
- 应用退出时先停止采集并关闭文件；网络请求可以取消，已经保存的音频不得删除。
- 数据库写操作使用短事务，禁止跨网络请求持有事务。

## 9. 隐私与日志

首版的本地 SQLite 会明文保存 API 密钥，这是明确接受的产品限制。仍必须做到：

- API 密钥不出现在 SwiftUI 可观察状态、日志、错误信息、崩溃报告和默认导出中。
- 设置页面仅返回遮罩值；更新密钥使用专门命令。
- 数据库和录音目录权限仅允许当前用户访问。
- 不采集遥测，不上传历史，不接入广告或会员服务。
- 只有用户触发转录或改写时，才向其选择的供应商发送音频或文字。
- 日志记录请求阶段、耗时、状态码和请求标识，不记录完整音频、原始文字、最终文字、密钥或鉴权头。
- 日志轮转并限制总容量，设置页可打开日志目录和清理日志。

## 10. 非功能要求

- 冷启动后应快速进入菜单栏可用状态，数据库迁移失败时不得继续录音。
- 任何失败都应有用户可理解的信息和可执行的下一步。
- 单次长录音应流式写盘，内存占用不随录音时长线性增长。
- 录音和数据库路径使用 Unicode 安全处理。
- 所有用户可见文本使用 String Catalog（`.xcstrings`）管理。
- 无网络时仍可浏览、搜索、复制、下载和删除历史。
- 应用升级不得删除录音、历史、密钥或用户设置。

## 11. 架构验收标准

- 拔网后完成一次录音，历史中出现可播放录音和可重试失败状态。
- 转录成功、改写失败时可看到原始文字，并可仅重试改写。
- 转录和改写成功、自动输入失败时最终文字仍可复制。
- 强制结束应用后重新启动，处于中间状态的记录按恢复规则变为可操作状态。
- 连续快速按快捷键不会创建多个并发录音。
- 切换 OpenAI 与 Anthropic 改写配置无需修改口述流程代码。
- SQLite 中保存相对录音路径，移动数据根目录后可重新定位。
- SwiftUI 视图中不存在直接 SQL、API 密钥或供应商鉴权逻辑。
- macOS 专用调用全部位于平台实现目录，领域核心可在非 macOS 环境执行单元测试。
