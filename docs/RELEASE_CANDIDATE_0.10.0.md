# VoiceCore 0.10.0 本地发布候选记录

- 构建日期：2026-08-07
- 版本：0.10.0（构建 2）
- Bundle ID：`dev.voicecore.app`
- 最低系统：macOS 14
- 架构：Apple Silicon `arm64`
- Archive：`build/VoiceCore.xcarchive`
- DMG：`build/VoiceCore.dmg`
- DMG SHA-256：`21e04108983c400995575b727f2b37c673273c58342bb11ef5d28a944334bd5d`

## 本版变化

- 新增火山引擎豆包“录音文件极速版”原生语音识别协议。
- 新增 M4A/AAC 到 16 kHz 单声道 PCM WAV 的本机转码，不修改永久录音原文件。
- 设置页可选择“豆包录音文件极速版”，并支持保存、设为默认和测试连接。
- 解析豆包 `X-Api-Status-Code`，区分无语音、音频格式错误、配置错误和可重试的服务繁忙。
- URLSession 响应摘要新增小写响应头字典，并继续对鉴权头脱敏。

## 已验证

- 豆包真实接口：业务状态 `20000000`，中英混合测试音频转录成功。
- SwiftFormat：0 个文件待格式化。
- SwiftLint strict：0 个违规。
- Swift Package XCTest：198/198 通过（Domain 49、Application 33、Data 52、Providers 58、Audio 2、Platform 4）。
- App XCTest：15/15 通过。
- macOS XCUITest：5/5 通过。
- 模型模拟服务器：18/18 场景通过。
- `xcodebuild archive` 成功；归档应用 `codesign --verify --deep --strict` 通过。
- DMG 经 `hdiutil verify` 校验有效。

## 本地候选限制

- 当前使用“Sign to Run Locally”临时签名，未使用 Developer ID，也未进行 Apple 公证，只适合本机开发和验收。
- 豆包协议当前使用文件极速版，不提供边说边出的流式部分结果。
- 豆包文件极速版当前不声明词典热词能力；词典仍用于 OpenAI 兼容语音模型和文字改写模型。
- 仍需用户用真实麦克风完成独立 `Fn`、中文/英文/中英混合及跨应用自动输入人工验收。
