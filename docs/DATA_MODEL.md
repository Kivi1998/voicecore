# OpenTypeless 数据模型与迁移规范

## 1. 数据原则

- SQLite 保存所有结构化本地数据，是记录状态的唯一真相来源。
- 所有录音永久保存在文件系统，数据库只保存相对路径和校验信息。
- API 密钥首版以明文保存于 SQLite；不得通过普通查询命令返回前端。
- 所有时间以 UTC 的 RFC 3339 字符串或整数毫秒保存，展示时按系统时区转换。
- 所有主键使用 UUID 文本，避免未来跨设备导入时冲突。
- 删除口述记录时，数据库删除和文件删除要以可恢复顺序执行。
- 所有表必须由版本化迁移创建，禁止运行时按缺列临时修补。

## 2. 数据目录

```text
~/Library/Application Support/<bundle-id>/
├── app.sqlite3
├── recordings/
│   └── 2026/08/06/<record-id>.m4a
├── temp/
├── logs/
└── backups/
```

`recordings/` 中的路径在数据库保存为相对值，例如 `2026/08/06/<record-id>.m4a`。临时转码文件放在 `temp/`，请求结束后可删除；原录音不得被临时文件覆盖。

## 3. 枚举定义

### 3.1 记录状态

```text
created
recording
audio_saved
transcribing
transcription_failed
transcribed
rewriting
rewrite_failed
ready
injecting
injection_failed
completed
recording_failed
cancelled
```

### 3.2 提供商用途

```text
speech
rewrite
```

### 3.3 协议类型

```text
openai_audio_transcription
qwen_native
doubao_native
openai_chat
anthropic_messages
```

千问原生和豆包原生是预留扩展值；未实现的协议不得在界面中显示为可用。

### 3.4 错误类别

```text
permission_denied
device_unavailable
audio_write_failed
audio_invalid
configuration_invalid
authentication_failed
rate_limited
network_unavailable
provider_timeout
provider_rejected
provider_bad_response
rewrite_failed
injection_permission_denied
injection_target_unavailable
app_interrupted
unknown
```

## 4. 核心表

以下为逻辑结构；具体 SQLite 类型和索引由首个迁移实现。

### 4.1 `dictation_records`

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | TEXT | 主键 | UUID |
| `status` | TEXT | 非空 | 当前状态 |
| `started_at` | TEXT | 非空 | 开始录音 UTC 时间 |
| `stopped_at` | TEXT | 可空 | 用户停止或采集结束时间 |
| `completed_at` | TEXT | 可空 | 全流程完成时间 |
| `duration_ms` | INTEGER | 非空默认 0 | 录音时长 |
| `audio_rel_path` | TEXT | 可空 | 相对录音根目录路径 |
| `audio_mime_type` | TEXT | 可空 | 例如 `audio/mp4` |
| `audio_size_bytes` | INTEGER | 可空 | 文件大小 |
| `audio_sha256` | TEXT | 可空 | 完整性校验，可异步生成 |
| `raw_transcript` | TEXT | 可空 | 语音识别原文 |
| `final_text` | TEXT | 可空 | 最终使用文字 |
| `count_units` | INTEGER | 非空默认 0 | 统计单位数 |
| `detected_language` | TEXT | 可空 | 供应商返回或推断语言 |
| `is_favorite` | INTEGER | 非空默认 0 | 0/1 |
| `speech_profile_id` | TEXT | 可空外键 | 使用的语音配置 |
| `rewrite_profile_id` | TEXT | 可空外键 | 使用的改写配置；关闭改写可空 |
| `speech_snapshot_json` | TEXT | 非空 | 当次协议、端点、模型的脱敏快照 |
| `rewrite_snapshot_json` | TEXT | 可空 | 当次改写配置脱敏快照 |
| `last_error_category` | TEXT | 可空 | 标准错误类别 |
| `last_error_message` | TEXT | 可空 | 用户可理解且已脱敏的信息 |
| `retry_count` | INTEGER | 非空默认 0 | 总重试次数 |
| `created_at` | TEXT | 非空 | 创建时间 |
| `updated_at` | TEXT | 非空 | 最近修改时间 |

配置快照不得包含 API 密钥、完整自定义鉴权头或其他秘密。删除模型配置后历史仍能说明当时使用了哪个模型。

推荐索引：

- `started_at DESC`：历史分页和时间范围。
- `(status, started_at DESC)`：失败筛选。
- `(is_favorite, started_at DESC)`：收藏筛选。
- `speech_profile_id`、`rewrite_profile_id`：配置引用检查。

历史列表必须使用游标或稳定分页，不允许一次加载全部记录。

### 4.2 `record_attempts`

记录每次转录、改写或输入尝试，便于诊断和审查。

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT 主键 | UUID |
| `record_id` | TEXT 外键 | 关联口述记录，删除时级联 |
| `stage` | TEXT | `transcription`、`rewrite`、`injection` |
| `attempt_no` | INTEGER | 同阶段从 1 开始 |
| `provider_kind` | TEXT 可空 | 协议类型 |
| `model_name` | TEXT 可空 | 模型名 |
| `started_at` | TEXT | 开始时间 |
| `finished_at` | TEXT 可空 | 结束时间 |
| `success` | INTEGER 可空 | 完成前为空 |
| `http_status` | INTEGER 可空 | HTTP 状态 |
| `provider_request_id` | TEXT 可空 | 供应商请求标识 |
| `error_category` | TEXT 可空 | 标准错误类别 |
| `error_message` | TEXT 可空 | 已脱敏错误 |
| `latency_ms` | INTEGER 可空 | 阶段耗时 |

不得保存请求正文、鉴权头、完整供应商响应或用户音频。

### 4.3 `provider_profiles`

| 字段 | 类型 | 约束与说明 |
|---|---|---|
| `id` | TEXT | 主键 UUID |
| `name` | TEXT | 非空，用户可见名称 |
| `purpose` | TEXT | `speech` 或 `rewrite` |
| `protocol` | TEXT | 协议枚举 |
| `base_url` | TEXT | 非空，必须是 HTTPS；本机地址可允许 HTTP |
| `model_name` | TEXT | 非空 |
| `api_key` | TEXT | 首版明文保存，可空以支持无鉴权本地服务 |
| `custom_headers_json` | TEXT | JSON 对象；前端显示时敏感值遮罩 |
| `options_json` | TEXT | 协议扩展参数，不得滥用为核心字段替代品 |
| `is_enabled` | INTEGER | 是否可选 |
| `is_default` | INTEGER | 同一用途最多一个默认配置 |
| `created_at` | TEXT | 创建时间 |
| `updated_at` | TEXT | 修改时间 |

数据库通过事务确保每种 `purpose` 最多一个默认配置。删除正在被历史引用的配置时，推荐软删除或阻止删除并提供“停用”；禁止让历史外键失效。

完整密钥只能通过后端专用写命令新增或替换。常规读取返回：

```json
{
  "hasApiKey": true,
  "apiKeyMasked": "sk-••••••••abcd"
}
```

前端永远不需要获取完整密钥。

### 4.4 `dictionary_terms`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | TEXT 主键 | UUID |
| `term` | TEXT | 原始词语 |
| `normalized_term` | TEXT | 去除首尾空白及大小写归一结果 |
| `created_at` | TEXT | 添加时间 |
| `updated_at` | TEXT | 修改时间 |

`normalized_term` 建唯一索引。首版仅允许单个非空词语，设置合理最大长度，不做自动学习和复杂替换规则。

### 4.5 `app_settings`

键值配置表只保存非秘密、低频设置。

| 字段 | 类型 | 说明 |
|---|---|---|
| `key` | TEXT 主键 | 稳定配置键 |
| `value_json` | TEXT | JSON 值 |
| `updated_at` | TEXT | 修改时间 |

建议键包括：快捷键、麦克风设备标识、自动输入、提示音、开机启动、程序坞显示、界面语言、日志级别、周起始日、录音根目录。核心结构化实体不得塞进该表。

### 4.6 `schema_migrations`

| 字段 | 类型 | 说明 |
|---|---|---|
| `version` | INTEGER 主键 | 单调递增版本号 |
| `name` | TEXT | 迁移名称 |
| `checksum` | TEXT | 文件校验值 |
| `applied_at` | TEXT | 执行时间 |

## 5. 删除和文件一致性

用户删除一条记录时：

1. 在事务中把记录标记为待删除，或写入删除队列表。
2. 提交事务。
3. 删除对应录音文件和可派生临时文件。
4. 在第二个事务中删除数据库记录及尝试记录。
5. 文件删除失败时保留待删除状态，后台重试并向用户显示占用。

不能先永久删除数据库记录再尝试寻找文件。若文件不存在，记录仍可删除，但日志需要记录缺失情况。

首版没有“批量自动清理录音”；所有录音永久保存，只有用户明确执行删除才移除。

## 6. 统计查询

统计只计算存在 `final_text` 的记录，不以自动输入是否成功作为排除条件。原因是输入失败不代表口述失败。

推荐规则：

- 中文、日文、韩文字符逐字计数。
- 连续的拉丁字母或数字组成一个词。
- Emoji、纯标点、空白不计。
- 统计值在最终文字保存时写入 `count_units`，算法升级不得默默改写既有记录。

首页查询：

- 今日：按当前时区计算 UTC 边界，聚合 `count_units`、`duration_ms` 和记录数。
- 本周：星期一至当前时间。
- 总量：所有有效最终文字记录。
- 最近趋势：按本地日期分组最近七天。

## 7. 全文搜索

第一版数据量较小时可对 `raw_transcript` 和 `final_text` 使用参数化 `LIKE` 查询。达到性能阈值后迁移到 SQLite FTS5 虚拟表，并使用触发器或应用层事务保持同步。

搜索不得扫描或索引 API 密钥、错误详情及自定义请求头。

## 8. 数据库迁移规范

- 迁移文件命名为 `0001_initial.sql`、`0002_add_xxx.sql`。
- 已发布迁移不可修改；只能追加新迁移。
- 启动时在打开主窗口业务功能前执行迁移。
- 每个迁移在事务中执行；不支持事务的操作必须有备份和恢复设计。
- 迁移失败时应用进入只读错误页面，禁止录音和继续写入。
- 发布前用空数据库、上一正式版本数据库和包含大量数据的数据库验证迁移。
- 破坏性迁移前创建数据库备份，但不得复制全部录音。
- `schema_migrations.checksum` 用于发现已发布迁移被篡改。

## 9. 导入、导出与备份

首版至少提供：

- 打开数据目录。
- 导出选定录音文件。
- 下载单条录音。
- 数据库备份说明。

如果提供“完整备份”，必须明确提示其中包含明文 API 密钥。普通历史导出默认仅包含时间、状态、文字、收藏和可选录音，不包含密钥、鉴权头和内部错误堆栈。

## 10. 数据模型测试与验收

- 空数据库可以一次迁移到最新版本。
- 上一版本数据库可迁移且记录数、收藏、文字和录音路径保持一致。
- 同一归一化词语不能重复添加。
- 同一用途不能存在两个默认提供商配置。
- 普通配置查询不会返回完整 API 密钥。
- 状态更新和文字写入在同一事务失败时均不生效。
- 删除记录时文件删除失败不会产生不可追踪孤儿文件。
- 应用异常退出后，中间状态记录可被恢复器发现。
- 日期跨午夜和跨时区时，今日与本周统计正确。
- 十万条历史记录下分页、日期筛选和失败筛选保持可接受响应时间。
