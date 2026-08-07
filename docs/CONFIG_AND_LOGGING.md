# 配置分层与敏感日志规范（FND-004）

## 1. 配置分层（优先级从高到低）

1. **数据库应用设置**：用户在设置页的显式选择（`app_settings` 表），
   包括改写开关、自动输入、剪贴板恢复、语言提示、快捷键、默认模型配置。
2. **环境变量**：仅开发期覆盖（见 `.env.example`）；release 构建不读取。
   密钥类配置**禁止**走环境变量。
3. **代码内默认值**：`PipelineOptions`、适配器默认超时等为最终兜底。

运行时快照：流水线开始时由 `PipelineOptionsProvider` 读取设置生成
`PipelineOptions`，会话中途改设置不影响进行中的会话。

## 2. 密钥生命周期（安全红线）

- 密钥只存 `provider_profiles.api_key` 列（SQLite，数据目录 0700）；
- 界面只读取 `MaskedSecret` 遮罩；完整密钥只经 `secrets(id:)` 专用通道，
  且只能流向适配器请求头构造；
- 密钥不得出现在：SwiftUI 可观察状态、日志、错误信息、崩溃报告、
  默认导出（`HistoryExportEnvelope` 只含脱敏快照）、测试快照、示例文件。

## 3. 日志脱敏规则（有自动测试）

- 统一使用 `LogRedactor`（`OpenTypelessProviders/HTTP`）：
  - `redact(_:)`：Bearer 令牌与常见密钥形态（`sk-` 等）替换为 `•••`；
  - `redactedHeaders(_:)`：Authorization、x-api-key、api-key、
    proxy-authorization、x-auth-token 头值替换为 `•••`。
- 请求日志只允许输出：方法、端点（不含查询串）、状态码、耗时、
  脱敏后的头；禁止输出请求/响应正文中的音频与文字内容。
- 错误信息面向用户且已脱敏（`DictationError.userMessage`）；
  供应商原始错误正文不进日志正文，只保留类别与状态码。
- 剪贴板快照、口述文字、音频文件内容不得写入任何日志。
- SwiftLint 自定义规则 `no_secrets_in_logs` 在 CI 拦截疑似明文输出。

## 4. 仓库卫生

- 仓库不得出现真实密钥；`.env` 在 `.gitignore`，`.env.example` 只含
  非敏感默认值并显式说明不提供密钥变量。
- 提交前检查：`git grep -nE 'sk-[A-Za-z0-9]{8,}|Bearer [A-Za-z0-9._-]{8,}'`
  应无业务代码命中。
