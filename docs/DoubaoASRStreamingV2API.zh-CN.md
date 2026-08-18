# 豆包流式语音识别 2.0 接口文档

> 来源：火山引擎官方文档 [大模型流式语音识别API](https://docs.volcengine.com/docs/6561/1354869?lang=zh)（最近更新时间 2026.08.06）。
>
> 本文只整理 2.0（`seedasr`）路径需要的字段，1.0/2.0 共用同一套协议和接口地址，仅 `X-Api-Resource-Id` 不同。

## 现状对照

Voicecore 当前实现：`Voicecore/Core/RemoteProviders/DoubaoASRConfiguration.swift`。

- 默认模型已经是 2.0：`modelV2 = "volc.seedasr.sauc.duration"`（`resolvedResourceID` 在 `model` 为空时返回 `modelV2`）。
- 默认走的接口地址是 `defaultStreamingEndpointV2 = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"`，即官方文档里的**双向流式模式（优化版本）**。
- **流式这条链路本身已经是 2.0，不需要迁移**，本文档仅作为字段参考，供后续调参/排查问题使用。

## 接口地址（三选一）

| 模式 | 地址 | 特点 |
|---|---|---|
| 双向流式模式 | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel` | 每包音频对应一包返回，速度快 |
| 双向流式模式（优化版本） | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async` | **Voicecore 默认用这个**；只有结果变化时才返回新包，RTF、首字/尾字时延更优 |
| 流式输入模式 | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream` | 音频满 15s 或收到最后一包才返回，准确率更高但不是"边说边出字" |

- 单包音频建议 100~200ms，双向流式模式（优化版）建议 200ms 一包，发包间隔 100~200ms，不宜过大或过小。
- 流式输入模式在平均音频时长 5s 时，可做到 300~400ms 内返回。

## 鉴权（WebSocket 握手 Header）

新版控制台只需要 `X-Api-Key`；Voicecore 用的是旧版控制台方式（`X-Api-App-Key` + `X-Api-Access-Key`），两者等价。

| Key | 说明 | 示例 |
|---|---|---|
| X-Api-App-Key / X-Api-Key | APP ID / APP Key | 123456789 |
| X-Api-Access-Key | Access Token（旧版控制台才需要） | your-access-key |
| X-Api-Resource-Id | 见下表 | volc.seedasr.sauc.duration |
| X-Api-Connect-Id | 建连时用，随机 UUID | 67ee89ba-... |
| X-Api-Sequence | 固定值 `-1` | -1 |

**Resource ID 对照表**：

| 版本 | 计费方式 | Resource ID |
|---|---|---|
| 1.0 | 小时版 | `volc.bigasr.sauc.duration` |
| 1.0 | 并发版 | `volc.bigasr.sauc.concurrent` |
| **2.0** | **小时版（Voicecore 默认）** | **`volc.seedasr.sauc.duration`** |
| 2.0 | 并发版 | `volc.seedasr.sauc.concurrent` |

握手成功后服务端会返回 `X-Api-Connect-Id` 和 `X-Tt-Logid`（排错用，建议记录）。

## 二进制协议

WebSocket frame payload 用自定义二进制协议，由 `header`（4 字节）+ `payload size`（4 字节大端 uint32）+ `payload` 组成，整数字段一律大端。

### Header（4 字节）

| 字节 | 内容 | 说明 |
|---|---|---|
| 0 | Protocol version (4bit) + Header size (4bit) | version 目前固定 `0b0001`；header size `0b0001` 表示 4 字节 |
| 1 | Message type (4bit) + Message type specific flags (4bit) | 见下表 |
| 2 | Message serialization method (4bit) + Message compression (4bit) | 序列化：`0b0000`=无 / `0b0001`=JSON；压缩：`0b0000`=无 / `0b0001`=Gzip |
| 3 | Reserved | 固定 `0x00`，仅做 4 字节对齐填充 |

**Message type**：

- `0b0001` full client request（端上发送请求参数）
- `0b0010` audio only request（端上发送音频数据）
- `0b1001` full server response（服务端下发识别结果）
- `0b1111` error message（服务端处理错误）

**Message type specific flags**：

- `0b0000` header 后 4 字节不是 sequence number
- `0b0001` header 后 4 字节是正数 sequence number
- `0b0010` header 后 4 字节不是 sequence number，仅表示这是最后一包（负包）
- `0b0011` header 后 4 字节是 sequence number 且为负数（最后一包）

### full client request（首个请求）

`Header(4B)` + `Payload size(4B, uint32 大端)` + `Payload(JSON，按 header 声明的方式序列化/压缩)`

Payload 字段（`request` 必填，`audio` 必填）：

| 字段 | 层级 | 必填 | 备注 |
|---|---|---|---|
| `user.uid` / `did` / `platform` / `sdk_version` / `app_version` | 2 | 否 | 仅用于日志过滤 |
| `audio.language` | 2 | 否 | **仅流式输入模式（`bigmodel_nostream`）支持**，双向流式（含优化版）不支持；为空时默认支持中英文+多方言，可设为 `zh-CN`/`en-US` 等指定语种 |
| `audio.format` | 2 | **✓** | `pcm` / `wav` / `ogg` / `mp3`；pcm 和 wav 的内部音频流必须是 `pcm_s16le` |
| `audio.codec` | 2 | 否 | `raw`/`opus`，默认 `raw`(pcm)；format=ogg 时必须是 opus，format=mp3 时此字段不生效 |
| `audio.rate` | 2 | 否 | 默认 16000，**目前只支持 16000** |
| `audio.bits` | 2 | 否 | 默认 16，**暂只支持 16bits** |
| `audio.channel` | 2 | 否 | 1(mono)/2(stereo)，默认 1 |
| `request.model_name` | 2 | **✓** | 目前只有 `bigmodel` |
| `request.enable_nonstream` | 2 | 否 | 开启"二遍识别"（流式实时上屏 + nostream 二次识别提升准确率），**仅双向流式优化版支持**，开启后默认启用 VAD 分句（800ms 判停） |
| `request.enable_itn` | 2 | 否 | 默认 **true** |
| `request.enable_punc` | 2 | 否 | 默认 **true**（注意：这点跟文件识别标准版不同，文件识别默认是 false） |
| `request.enable_ddc` | 2 | 否 | 默认 false，语义顺滑 |
| `request.enable_speaker_info` | 2 | 否 | 说话人分离，默认不开启；需配合 `ssd_version="200"`，建议仅 2.0 开启 |
| `request.output_zh_variant` | 2 | 否 | `traditional`/`tw`/`hk`，简体转繁体 |
| `request.enable_auto_lang` | 2 | 否 | **仅流式输入模式支持**，25 语种自动识别 |
| `request.show_utterances` | 2 | 否 | 输出分句/分词/停顿信息 |
| `request.show_speech_rate` / `show_volume` / `enable_lid` / `enable_emotion_detection` / `enable_gender_detection` | 2 | 否 | **仅 nostream 接口和双向流式优化版支持** |
| `request.result_type` | 2 | 否 | `full`(默认，全量返回) / `single`(增量返回) |
| `request.enable_accelerate_text` + `accelerate_score` | 2 | 否 | 首字加速，`accelerate_score` 取值 0-20，越大越快但首字准确率越低 |
| `request.vad_segment_duration` | 2 | 否 | 语义切句最大静音阈值，默认 3000ms |
| `request.end_window_size` | 2 | 否 | 强制判停时间，默认 800ms，最小 200ms |
| `request.force_to_speech_time` | 2 | 否 | 强制语音时间，配合 `end_window_size` 用，推荐 1000ms |
| `request.corpus.boosting_table_name/id` `correct_table_name/id` `context` | 3 | 否 | 热词/替换词/上下文，**2.0 支持在 context 中传 `image_url`**（≤500KB，最多1张） |

请求示例（官方原文）：

```json
{
  "user": { "uid": "388808088185088" },
  "audio": {
    "format": "wav",
    "rate": 16000,
    "bits": 16,
    "channel": 1,
    "language": "zh-CN"
  },
  "request": {
    "model_name": "bigmodel",
    "enable_itn": false,
    "enable_ddc": false,
    "enable_punc": false
  }
}
```

### audio only request（后续音频包）

格式同上，`Payload` 是压缩后的原始音频字节。可以多次发送，每包对应一段音频时长。最后一包需要在 `Message type specific flags` 里标记为负包（`0b0010`/`0b0011`）。

### full server response（服务端识别结果）

`Header(4B)` + `Sequence(4B)` + `Payload size(4B)` + `Payload(JSON)`

```json
{
  "audio_info": { "duration": 3696 },
  "result": {
    "text": "这是字节跳动， 今日头条母公司。",
    "utterances": [
      {
        "definite": true,
        "start_time": 0,
        "end_time": 1705,
        "text": "这是字节跳动，",
        "words": [ { "text": "这", "start_time": 740, "end_time": 860, "blank_duration": 0 } ]
      }
    ]
  }
}
```

`utterances[].definite = true` 表示这是一个确定分句（`show_utterances` 开启时才有）。

### error message（协议级错误）

`Header(4B)` + `Error code(4B uint32)` + `Error message size(4B uint32)` + `Error message(UTF8 string)`。

## 错误码

| 错误码 | 含义 |
|---|---|
| 20000000 | 成功 |
| 45000001 | 请求参数无效（缺必填字段/字段值无效/重复请求） |
| 45000002 | 空音频 |
| 45000081 | 等包超时 |
| 45000151 | 音频格式不正确 |
| 550xxxxx | 服务内部处理错误 |
| 55000031 | 服务器繁忙 |
