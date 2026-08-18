# 豆包录音文件识别 2.0 接口文档

> 来源：火山引擎官方文档 [录音文件识别标准版HTTP](https://docs.volcengine.com/docs/6561/1354868?lang=zh)、[产品简介](https://docs.volcengine.com/docs/6561/1354871?lang=zh)、[计费说明](https://docs.volcengine.com/docs/6561/1359370?lang=zh)。
>
> 1.0（`volc.bigasr.auc`）和 2.0（`volc.seedasr.auc`）共用同一套 submit/query 接口，仅 `X-Api-Resource-Id` 不同。

## 现状对照

Voicecore 当前实现：`Voicecore/Transcription/RemoteASR/RemoteASRTranscriber.swift` 的 `doubaoFlashFileConfiguration`（约第 652-659 行），把文件识别写死成：

```swift
resolved.model = DoubaoASRConfiguration.flashRecognitionModelTurbo  // "volc.bigasr.auc_turbo"
resolved.endpoint = DoubaoASRConfiguration.resolvedFlashRecognitionEndpoint(configuration.endpoint)
// -> https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash
```

`volc.bigasr.auc_turbo` 是 **1.0 世代的极速版**，走的是同步单次接口（`/recognize/flash`），不是本文档说的 submit/query 异步接口，也不属于 2.0。本文档整理的是 2.0 唯一可用的形态——**标准版 submit/query 异步接口**，用于后续把文件识别迁移到 2.0。

## 接口一：提交任务

**地址**：`POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/submit`

### Header

| Key | 说明 | 值 |
|---|---|---|
| X-Api-App-Key | APP ID（Voicecore 走旧版控制台鉴权） | 8300509985 |
| X-Api-Access-Key | Access Token | — |
| X-Api-Resource-Id | **`volc.seedasr.auc`**（2.0）；1.0 是 `volc.bigasr.auc` | volc.seedasr.auc |
| X-Api-Request-Id | 随机 UUID，提交和查询要用同一个 | — |
| X-Api-Sequence | 固定值 `-1` | -1 |

### Body 字段（官方文档表）

```json
{
  "user": { "uid": "388808087185088" },
  "audio": {
    "format": "mp3",
    "url": "http://xxx.com/obj/sample.mp3"
  },
  "request": {
    "model_name": "bigmodel",
    "enable_itn": true
  }
}
```

| 字段 | 层级 | 必填 | 备注 |
|---|---|---|---|
| `user.uid` | 2 | 否 | 建议 IMEI 或 MAC |
| `audio` | 1 | **✓** | |
| `audio.url` | 2 | **✓** | 音频链接——**文档里只写了这一个字段，没有 `data`** |
| `audio.format` | 2 | **✓** | `raw`/`wav`/`mp3`/`ogg` |
| `audio.language` | 2 | 否 | 为空时默认支持中英文+方言 |
| `audio.codec` | 2 | 否 | `raw`/`opus`，默认 `raw`(pcm) |
| `audio.rate` / `bits` / `channel` | 2 | 否 | 默认 16000 / 16 / 1(mono) |
| `request` | 1 | **✓** | |
| `request.model_name` | 2 | **✓** | 目前只有 `bigmodel` |
| `request.enable_itn` | 2 | 否 | 默认 **true** |
| `request.enable_punc` | 2 | 否 | 默认 **false**（跟流式接口默认 true 不一样，要注意） |
| `request.enable_ddc` | 2 | 否 | 默认 false |
| `request.enable_speaker_info` | 2 | 否 | 说话人分离，默认 false，10 人以内效果较好；需配合 `ssd_version="200"` |
| `request.enable_channel_split` | 2 | 否 | 双声道识别，`channel_id` 标记左右声道 |
| `request.show_utterances` / `show_speech_rate` / `show_volume` | 2 | 否 | 分句/语速/音量信息 |
| `request.enable_lid` / `enable_emotion_detection` / `enable_gender_detection` | 2 | 否 | 语种/情绪/性别检测——**这几项 1.0 极速版（auc_turbo）不支持，2.0 标准版支持** |
| `request.vad_segment` / `end_window_size` | 2 | 否 | 分句方式与判停时间(300-5000ms) |
| `request.sensitive_words_filter` | 2 | 否 | 敏感词过滤 |
| `request.enable_poi_fc` / `enable_music_fc` | 2 | 否 | 地图/音乐领域推荐词辅助识别 |
| `request.corpus.context` | 3 | 否 | 热词/上下文，**2.0 支持传 `image_url`**（≤500KB，最多1张，辅助识别） |
| `callback` / `callback_data` | 1 | 否 | 任务完成后的回调地址——**1.0 极速版不支持，2.0 标准版支持** |

### 响应（只有 Header，Body 为空）

| Header | 说明 |
|---|---|
| `X-Api-Status-Code` | `20000000` = 提交成功，其他 = 失败 |
| `X-Api-Message` | `OK` 或错误信息 |
| `X-Tt-Logid` | 排错用 |

> **⚠️ 实测发现（未写入官方文档，不作为正式依赖）**：2026-08-17 用真实账号直接向 `audio` 传 `"data": "<base64>"`（不传 `url`）实测是能被接受并正常处理的（`X-Api-Status-Code: 20000000`）。但官方字段表**只列了 `url` 一个必填字段**，`data` 完全没有出现在文档里。正式实现应该按文档要求走 `audio.url`（即先把本地音频上传到一个可访问的 URL），`audio.data` 只能当作没有官方保障的临时验证手段。

## 接口二：查询结果

**地址**：`POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/query`

Header 同提交任务（不需要 `X-Api-Sequence`），Body 为空 JSON `{}`。

### 响应

`X-Api-Status-Code` 用于判断状态：

| 状态码 | 含义 |
|---|---|
| 20000000 | 成功，Body 里有识别结果 |
| 20000001 | 正在处理中 |
| 20000002 | 任务在队列中 |
| 20000003 | 静音音频，没有检测到人声 |
| 45000001 | 请求参数无效 |
| 45000002 | 空音频 |
| 45000131 | 超过半小时提交的音频长度上限（默认半小时最多提交 500 小时） |
| 45000132 | 超过音频大小限制（**单文件 < 512M**） |
| 45000151 | 音频格式不正确 |
| 55000031 | 服务器繁忙 |

成功时 Body 示例：

```json
{
  "audio_info": { "duration": 10000 },
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

## 使用限制与返回时效（官方产品页）

| 版本 | 返回时效 | 单文件限制 | 并发/QPS |
|---|---|---|---|
| 标准版（1.0/2.0 共用） | **3 小时内**（SLA 上限，非典型值） | 时长 <5小时，大小 <512M | 默认最大 20 QPS，半小时内提交音频总时长 ≤500 小时 |
| 极速版（仅 1.0 `auc_turbo`，App 现在用的） | 约 30 分钟音频 10 秒左右返回（不含传输） | ≤2小时 / ≤100MB | 默认 5 并发 |
| 闲时版（仅 1.0 `auc_idle`） | 24 小时内 | 同标准版 | — |

**实测延迟**（2026-08-17，真实账号，5 个真实录音样本，submit 用 `audio.data`）：

| 文件大小 | 总耗时（submit+query） |
|---|---|
| 200KB | 12.44s |
| 422KB | 40.83s |
| 780KB | 22.77s |
| 3.3MB | 37.50s |

全部在第一次轮询（提交后 2 秒）就拿到结果，说明真实处理速度远快于"3小时"SLA上限，耗时波动主要来自提交阶段的网络环节，不是服务端排队。

## 价格对比（官方计费文档，后付费单价）

| 版本 | 后付费单价 | 相对 2.0 倍数 |
|---|---|---|
| 1.0 极速版 `auc_turbo`（App 现在用的） | 4.5 元/小时 | 5.6x |
| 1.0 标准版 `auc` | 2.3 元/小时 | 2.9x |
| 1.0 闲时版 `auc_idle` | 1.2 元/小时 | 1.5x |
| **2.0 标准版 `seedasr.auc`** | **0.8 元/小时** | 1x |

## 迁移到 2.0 需要改的地方

1. `DoubaoASRConfiguration.swift`：新增 `flashRecognitionModelV2Standard = "volc.seedasr.auc"` 常量，以及 `/api/v3/auc/bigmodel/submit`、`/api/v3/auc/bigmodel/query` 两个真实可用的 endpoint 常量（现有 `resolvedFlashRecognitionEndpoint` 会把这两个路径**重写回** `/recognize/flash`，这段逻辑需要去掉或改造）。
2. `RemoteASRTranscriber.swift`：新增一条 submit + 轮询 query 的调用路径，替代 `doubaoFlashFileConfiguration` 的同步单次调用；轮询间隔参考官方 demo 用 2~3 秒，超时时间建议 60~180 秒（实测最慢样本 40s 出结果）。
3. 音频传参：按文档要求传 `audio.url`；`audio.data` 只是验证用，不建议依赖。若坚持用 `audio.url`，需要先把本地音频上传到可访问地址（这块目前代码库里没有现成实现，`AliyunRemoteASRClient.swift` 有类似"上传拿 URL"的先例可以参考结构，但用的是 Aliyun 自己的领取上传凭证接口，不能直接照搬）。
