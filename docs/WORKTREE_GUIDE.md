# Git worktree 并行开发指南

本文说明如何在不制造大量冲突的前提下，由 4～6 个 Agent 并行开发。任务定义、依赖和验收以根目录 `tasklist.md` 为准。

## 1. 基本原则

1. 设置一个只负责合并和门禁的集成负责人，不在集成分支直接开发功能。
2. 每个 worktree 只拥有约定目录；跨目录修改必须先通知集成负责人。
3. 基础契约先合并，再开启实现型 worktree。不得让多个 Agent 各自发明相同接口。
4. 数据库迁移文件单一所有者，其他模块通过仓储接口使用数据库。
5. 公共 SwiftUI 设计系统与 Liquid Glass 兼容层单一所有者，页面 Agent 不自行修改语义样式。
6. 每一波结束后先集成、测试和冻结接口，再开始下一波。

## 2. 建议目录所有权

实际目录由 FND-002 确定，以下为应保持的逻辑边界：

| 所有者 | 独占范围 | 可读取但不应并行修改 |
|---|---|---|
| 基础/核心 Agent | `Packages/OpenTypelessDomain/`、`Packages/OpenTypelessApplication/` | AppKit、AVFoundation 与模型实现 |
| 数据 Agent | `Packages/OpenTypelessData/`、数据迁移资源 | SwiftUI 页面和平台实现 |
| 模型 Agent | `Packages/OpenTypelessProviders/`、URLSession 协议契约测试 | GRDB 仓储实现 |
| 平台 Agent | `Packages/OpenTypelessPlatform/`、`App/macOS/`、Entitlements/Info.plist | 核心状态机 |
| UI Agent | `App/DesignSystem/`、`App/Features/`、视图测试 | Domain/Data/Providers Packages |
| QA/发布 Agent | `Tests/`、XCUITest target、CI、Archive/DMG 和验收文档 | 功能代码，除非进入专门修复分支 |

Xcode 工程文件、根 `Package.swift`、Entitlements、Info.plist、公共 protocol 和数据库迁移都属于高冲突文件，必须指定单一所有者。

## 3. worktree 创建模板

以下目录仅为示例，集成负责人应从同一个已通过门禁的提交创建：

```bash
git worktree add ../opentypeless-core -b feat/w2-core-engine integration
git worktree add ../opentypeless-data -b feat/w2-data-storage integration
git worktree add ../opentypeless-speech -b feat/w2-speech-providers integration
git worktree add ../opentypeless-rewrite -b feat/w2-rewrite-providers integration
git worktree add ../opentypeless-platform -b feat/w2-macos-platform integration
git worktree add ../opentypeless-ui -b feat/w3-ui-foundation integration
```

每个 Agent 开工前执行：

```bash
git status --short
git log -1 --oneline
```

确认工作区干净且基线提交正确。分支统一为 `<类型>/w<波次>-<模块>`；单任务修复仍采用 `tasklist.md` 中的建议分支名。完成后以 PR 或明确提交交给集成负责人；不要让 Agent 直接合并彼此分支。

## 4. 六波并行计划

### 第 0 波：单线程工程基线

目标：通过 G0，暂不并行，以免项目骨架和工具配置互相覆盖。

| worktree | 任务 | 独占文件 |
|---|---|---|
| `bootstrap` | FND-001～005 | Xcode 工程、Swift Packages、依赖、CI、签名基线 |

完成后打集成标签或记录基线提交，例如 `g0-baseline`。

### 第 1 波：最多 5 路冻结接口

目标：通过 G1。各 Agent 先提交设计和测试骨架，集成负责人统一处理公共类型冲突。

| worktree | 任务 | 前置 | 主要范围 |
|---|---|---|---|
| `core-contracts` | CORE-001 | G0 | 领域类型与状态定义 |
| `data-foundation` | DATA-001～002 | CORE-001 先合并 | 数据库迁移、仓储 |
| `stt-contract` | STT-001 | CORE-001 先合并 | 语音接口 |
| `llm-contract` | LLM-001 | CORE-001 先合并 | 改写接口 |
| `platform-contract` | PLAT-001 | CORE-001 先合并 | 平台能力接口 |

严格说 CORE-001 是本波内的微型前置任务：先快速合并，然后其余四路并行。G1 结束后冻结接口；若确需变更，必须由接口所有者单独提交。

### 第 2 波：6 路核心实现

目标：形成可用核心闭环的组成部分，但先不要求完整 UI。

| worktree | 任务 | 依赖 | 独占范围 |
|---|---|---|---|
| `core-engine` | CORE-002～005 | DATA-002、STT-002、LLM-002、PLAT-003/004 分批合并 | 核心状态机、流水线和自动输入编排 |
| `data-storage` | DATA-003～006 | DATA-001 | 文件与各仓储 |
| `speech-providers` | STT-002～005 | STT-001、DATA-005 接口 | 语音提供商 |
| `rewrite-providers` | LLM-002～004 | LLM-001、DATA-005 接口 | 文字提供商 |
| `macos-input` | PLAT-002、PLAT-004、PLAT-006 | PLAT-001 | 快捷键、输入、权限生命周期 |
| `macos-audio` | PLAT-003 | PLAT-001、DATA-003 接口 | 麦克风和录音 |

为避免循环等待，DATA-005 应尽早以小 PR 合并；模型 worktree 随后只依赖仓储接口。CORE-004 最后集成，不应让核心 Agent 复制模型或平台实现。

### 第 3 波：5 路产品功能

目标：通过 G3。此波先由 UI 基础 worktree 合并 UI-001、UI-002、UI-004；PLAT-005 合并后再由同一 UI 所有者完成 UI-006，避免并行修改悬浮条材质。

| worktree | 任务 | 依赖 | 独占范围 |
|---|---|---|---|
| `ui-foundation-home` | UI-001～006、CORE-006 | G2 核心接口；UI-006 等待 PLAT-005 | 设计系统、应用壳、首页、玻璃材质兼容层 |
| `history` | HIST-001～005 | SwiftUI 基础视图、DATA-002、CORE-004 | 历史服务与页面 |
| `dictionary` | DICT-001～003 | SwiftUI 基础视图、DATA-004 | 词典服务与页面 |
| `settings` | SET-001～004 | SwiftUI 基础视图、模型连接测试 | 设置服务与页面 |
| `menubar-overlay` | PLAT-005、PLAT-007 | CORE-004、PLAT-002 | MenuBarExtra、NSPanel 悬浮条、移动端边界 |

UI-001、UI-002、UI-004 与 UI-006 先以独立小 PR 合并，冻结 SwiftUI 设计系统、SF Symbols 语义和 Liquid Glass/旧系统材质兼容层；随后历史、词典、设置 Agent 只新增各自 Feature 目录。若缺少通用视图，由 UI 所有者补充。

### 第 4 波：4 路测试与发布准备

目标：通过 G4，功能分支原则上冻结。

| worktree | 任务 | 依赖 | 说明 |
|---|---|---|---|
| `backend-tests` | TEST-001、TEST-003 | G2 | 单元、集成、协议模拟测试 |
| `ui-tests` | TEST-002、TEST-007 | G3 | SwiftUI、XCUITest、视觉和辅助功能矩阵 |
| `macos-e2e` | TEST-004 | G3 | 必须在真实 Apple Silicon Mac 执行 |
| `release-candidate` | REL-001～002 | FND-005、TEST-004 | ARM64 应用、DMG、干净账户安装 |

测试 Agent 发现问题时只登记，不在测试分支顺手大改业务代码；缺陷应按模块回派。

### 第 5 波：独立审查、修复和最终交付

目标：通过 G5。审查者不得是核心功能的主要开发者。

| 顺序 | worktree | 任务 | 说明 |
|---:|---|---|---|
| 1 | `independent-review` | TEST-005 | 代码、安全、隐私、性能与需求覆盖审查 |
| 2 | `fix-<module>`（最多 4 路） | TEST-006 的模块修复部分 | 按 CORE、平台、模型、UI 分派，必须带复现测试 |
| 3 | `regression` | TEST-006 的全量回归部分 | 独立验证修复，不接受“开发者本机已通过”作为结论 |
| 4 | `final-docs-release` | REL-003～004 | 用户文档、校验值、发布说明和最终验收 |

## 5. 集成顺序与冲突控制

推荐集成顺序：

```text
基础契约 → 数据仓储 → 平台/模型实现 → 核心流水线 → UI 基础
→ 历史/词典/设置/悬浮条 → 测试 → 打包 → 独立审查 → 修复 → 回归 → 发布
```

高风险冲突处理：

- `.xcodeproj/project.pbxproj`、`Package.swift` 和包依赖：由基础负责人代为修改；其他 Agent 提交依赖申请。
- Entitlements、Info.plist、麦克风与辅助功能权限配置：仅平台 Agent 修改。
- 数据库迁移：仅数据 Agent 编号和创建。
- 公共 Swift 领域模型与 protocol：仅核心接口所有者修改。
- SwiftUI 语义样式、SF Symbols 映射、Liquid Glass 和材质降级层：仅 UI 基础 Agent 修改。
- NavigationSplitView 入口：UI 基础 Agent 预留页面目的地，页面 Agent 只实现各自 Feature。

## 6. Agent 交付模板

每个 Agent 完成任务时必须报告：

```text
任务 ID：
完成内容：
修改范围：
新增/变更接口：
执行的测试及结果：
未解决问题：
需要下游注意的约束：
建议合并顺序：
```

## 7. Kimi 开发后的审查闭环

Kimi 完成代码并不等于项目完成，必须按以下顺序执行：

1. 冻结功能提交，记录待审查的确切提交哈希。
2. 由独立 Agent 执行 TEST-005，逐条对照 `tasklist.md` 验收标准，不只看代码风格。
3. 重点审查录音永久保存、异常恢复、密钥泄露、全局快捷键、剪贴板恢复、URLSession 模型协议错误、GRDB 迁移、Swift 并发隔离、无会员功能残留，以及 Liquid Glass/旧系统降级和辅助功能。
4. 缺陷按严重级别登记：P0 数据丢失/不可使用/密钥泄露；P1 核心功能错误；P2 一般体验问题。
5. 将缺陷回派给对应模块 Agent；每个修复必须增加可复现测试。
6. 由不同 Agent 执行 TEST-006 全量回归和真实 Mac 验证。
7. 只有 P0/P1 清零、DMG 干净安装通过后，才允许 REL-003～004 完成最终交付。

## 8. 完成定义

一个任务只有同时满足以下条件才算完成：

- 输出内容已经合并到集成分支。
- `tasklist.md` 中的验收标准逐条满足。
- 自动测试通过，涉及 macOS 系统行为时具有真实设备记录。
- 没有把密钥、录音或用户文本写入日志。
- 没有未经说明地扩大权限或引入账号、会员、云同步功能。
- 下游所需接口和限制已有文档。
