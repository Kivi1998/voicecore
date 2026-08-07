# 跨 Apple 平台边界说明（PLAT-007）

本文固定 iPhone / iPad 扩展边界：哪些包今天就能在移动端编译，移动端
主应用与键盘扩展各自能做什么、不能做什么。首版只交付 macOS；
本文是预留边界说明，不引入任何移动端流程代码。

## 1. 共享包（macOS + iOS 双平台声明）

| 包 | iOS 可用性 | 说明 |
|---|---|---|
| `OpenTypelessDomain` | ✅ | 纯 Foundation：实体、状态机、协议、计数规则 |
| `OpenTypelessData` | ✅ | GRDB 支持 iOS；迁移、仓储、文件存储可直接复用（录音根目录改用 App Group 容器） |
| `OpenTypelessApplication` | ✅ | 编排、恢复、统计、生命周期与导出均为平台无关服务 |
| `OpenTypelessProviders` | ✅ | URLSession 适配器在 iOS 同样工作 |

四个包的 `Package.swift` 已声明 `.iOS(.v16)`；保持它们不导入
AppKit / SwiftUI / AVFoundation，任何违反都会在 macOS CI 编译时被发现。

## 2. macOS 专有包（不跨平台）

- `OpenTypelessPlatform`：AppKit / Carbon / AX / SMAppService 实现。
- `OpenTypelessAudio`：macOS 音频实现（iOS 需单独的音频会话实现，
  `AudioCapture` 协议可复用）。

## 3. iOS / iPadOS 主应用（未来）

- 可直接复用：SwiftUI 设计系统、领域实体、状态机、GRDB 仓储、统计、
  词典、URLSession 模型适配器、编排器与恢复服务。
- 必须重写：音频会话（`AVAudioSession` 录音权限与中断）、快捷键
  （iOS 无全局快捷键，改为 App 内录音入口）、注入（见下节）、
  路径服务（App Group 容器）。

## 4. 键盘扩展边界（硬性限制）

- 第三方键盘扩展**不能直接使用麦克风**：录音必须由主应用执行；
  扩展只能把已生成文字插入当前输入框。
- 数据交换经 App Group：主应用写入共享容器（数据库或只读导出文件），
  扩展只读；Deep Link 用于从扩展跳回主应用发起录音。
- 扩展进程内不加载 `OpenTypelessPlatform`，不发起模型网络请求
  （网络能力受扩展限制且体验不可控）；转录与改写只在主应用完成。
- 键盘扩展 UI 独立设计，不复用 macOS 悬浮条与菜单栏。

## 5. 不做的事（与范围约束一致）

- 不为移动端提前引入同步、账号、云流程；
- 不在首版代码中残留移动端半成品入口；
- Windows 复用仅限协议与数据库规范层面，不共享 Swift 实现。
