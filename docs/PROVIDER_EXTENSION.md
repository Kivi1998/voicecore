# 语音识别提供商扩展指南（STT-005）

本文面向新增语音识别适配器的开发者。目标：**新增适配器不需要修改录音、
流水线、历史、统计或输入模块**，只在 `VoiceCoreProviders` 增加文件并在
组合根登记。

协议细节见 `docs/PROVIDER_PROTOCOLS.md` §2–§5；本文是落地清单。

## 1. 扩展点总览

| 扩展点 | 位置 | 说明 |
|---|---|---|
| 协议契约 | `VoiceCoreDomain/SpeechProvider` | 唯一接口：`capabilities` / `validate()` / `transcribe(_:)` |
| 协议种类 | `ProviderProtocolKind.qwenNative` / `.doubaoNative` | 已预留，无需改枚举 |
| 能力声明 | `SpeechCapabilities` | 业务层只按能力调用，禁止按厂商名分支 |
| 组合根登记 | App 层 `ProviderFactory` 实现 | 按配置快照的 `protocolKind` 构造适配器 |
| 自动重试 | `RetryingSpeechProvider` 装饰器 | 包装即获得瞬态故障重试，无需适配器实现 |
| 错误归一化 | `ErrorCategory`（16 类） | 适配器必须把供应商错误码映射到统一类别 |

## 2. 新增适配器清单

1. 在 `Packages/VoiceCoreProviders/Sources/VoiceCoreProviders/Speech/`
   新建 `<Vendor>SpeechProvider.swift`，实现 `SpeechProvider`。
2. 专有配置（资源标识、区域、私有选项）定义类型化结构，序列化进
   `provider_profiles.options_json`（不得新增顶层密钥字段之外的明文字段）。
3. 鉴权头通过 `URLSessionTransport` 的保留头机制注入；密钥只来自
   `secrets(id:)` 专用通道，禁止写入日志（`LogRedactor` 兜底）。
4. 错误映射：认证 → `authenticationFailed`；限流 → `rateLimited`；
   超时 → `providerTimeout`；4xx → `providerRejected`（`isRetryable: false`）；
   5xx → `providerRejected`（可重试）；解析失败 → `providerBadResponse`。
5. 取消语义：Swift `Task` 取消必须传播为 `CancellationError`，不得映射为
   供应商故障，不得触发自动重试。
6. 在组合根 `ProviderFactory.makeSpeechProvider()` 按 `protocolKind` 登记。
7. 编写 MockTransport 契约测试：正常、限流、超时、畸形响应均可复现。

## 3. 鉴权扩展点

- OpenAI 兼容：`Authorization: Bearer <key>`（已实现，直接复用）。
- 千问原生：DashScope 密钥走同一 Bearer 通道；若未来使用临时令牌，
  令牌获取与缓存封装在适配器内，过期刷新不暴露到业务层。
- 豆包原生：录音文件极速版使用 `X-Api-Key` 与资源标识鉴权；资源标识存
  `options_json`，密钥仍只存 `api_key` 列并经 `secrets(id:)` 读取。

## 4. 流式扩展点

- 实时协议用 `URLSessionWebSocketTask`；部分结果只能作为会话事件，
  **只有最终结果写入 `raw_transcript`**。
- 本地录音写盘是恢复的唯一事实来源：流式会话失败不得删除音频，
  记录必须落到可重试状态（见 `docs/ARCHITECTURE.md` §5.1）。
- 停止录音后等待最终结果使用独立短超时；超时保留音频走文件方式重试。

## 5. 音频格式扩展点

- 首版统一采集 `m4a`（AAC）。适配器如需 PCM/WAV，在适配器内转码，
  录音模块与文件仓储不变。
- 文件校验（存在、非空、可读头）由 `AudioFileStore.finalize` 保证；
  格式级校验（采样率、声道）由音频模块负责，适配器假设输入可解码。

## 6. 原生适配状态

`QwenSpeechProviderSkeleton` 仍用于明确提示千问原生协议尚未实现。
`DoubaoSpeechProvider` 已实现录音文件极速版：通过 `WAVAudioTranscoder`
在本机将 AAC/M4A 转为 16 kHz 单声道 PCM WAV，再使用官方 JSON Base64
请求与 `X-Api-*` 响应头完成转录和错误映射。
