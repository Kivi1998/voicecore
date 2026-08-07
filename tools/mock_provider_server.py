#!/usr/bin/env python3
"""OpenTypeless 模型协议本地模拟服务器（TEST-003）。

仅用 Python 标准库，可重复模拟 OpenAI 语音、OpenAI 改写、Anthropic 改写
三条协议的正常与故障场景，供适配器契约测试与端到端演练使用。

用法：
    python3 tools/mock_provider_server.py [--port 8791]

场景以路径前缀选择，应用的基础地址填 `http://localhost:8791/<scenario>`：

    normal        正常成功响应（各端点返回协议规定结构）
    rate-limited  429 + Retry-After（限流，可重试）
    auth-failed   401（认证失败，不可重试）
    timeout       挂起不响应（默认 30s，可用 MOCK_TIMEOUT_SECONDS 调整）
    malformed     200 但返回截断的非法 JSON（解析错误）
    server-error  500（服务端错误）

端点（路径其余部分与真实协议一致）：
    POST <scenario>/v1/audio/transcriptions   OpenAI 语音（multipart）
    POST <scenario>/v1/chat/completions       OpenAI 改写
    POST <scenario>/v1/messages               Anthropic 改写

每个请求都会向 stdout 记录一行脱敏日志（不打印密钥，只记录是否存在鉴权头）。
"""

from __future__ import annotations

import argparse
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCENARIOS = {
    "normal",
    "rate-limited",
    "auth-failed",
    "timeout",
    "malformed",
    "server-error",
}

TRANSCRIPTION_OK = {"text": "模拟识别结果：你好，世界。"}
CHAT_OK = {
    "id": "chatcmpl-mock",
    "object": "chat.completion",
    "choices": [
        {
            "index": 0,
            "message": {"role": "assistant", "content": "模拟改写结果"},
            "finish_reason": "stop",
        }
    ],
}
MESSAGES_OK = {
    "id": "msg_mock",
    "type": "message",
    "role": "assistant",
    "content": [{"type": "text", "text": "模拟改写结果"}],
}


def _endpoint_kind(path_tail: str) -> str | None:
    if path_tail.endswith("/v1/audio/transcriptions"):
        return "transcription"
    if path_tail.endswith("/v1/chat/completions"):
        return "chat"
    if path_tail.endswith("/v1/messages"):
        return "messages"
    return None


class MockHandler(BaseHTTPRequestHandler):
    server_version = "OpenTypelessMock/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:  # 静默默认日志
        pass

    def _send_json(self, status: int, payload: dict, extra_headers: dict | None = None) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_raw(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802（stdlib 命名）
        parts = [p for p in self.path.split("/") if p]
        scenario = parts[0] if parts else ""
        path_tail = "/" + "/".join(parts[1:]) if len(parts) > 1 else "/"

        content_length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(content_length) if content_length else b""

        has_auth = bool(self.headers.get("Authorization") or self.headers.get("x-api-key"))
        print(
            f"[mock] POST {self.path} scenario={scenario or '-'} "
            f"auth={'yes' if has_auth else 'NO'} bytes={len(body)}",
            flush=True,
        )

        if scenario not in SCENARIOS:
            self._send_json(404, {"error": {"message": f"未知场景 '{scenario}'，可用：{sorted(SCENARIOS)}"}})
            return

        kind = _endpoint_kind(path_tail)
        if kind is None:
            self._send_json(404, {"error": {"message": f"未知端点 '{path_tail}'"}})
            return

        if scenario == "rate-limited":
            self._send_json(
                429,
                {"error": {"message": "模拟限流", "type": "rate_limit_error"}},
                extra_headers={"Retry-After": "1"},
            )
            return
        if scenario == "auth-failed":
            self._send_json(401, {"error": {"message": "模拟认证失败", "type": "authentication_error"}})
            return
        if scenario == "server-error":
            self._send_json(500, {"error": {"message": "模拟服务端错误", "type": "server_error"}})
            return
        if scenario == "timeout":
            time.sleep(float(os.environ.get("MOCK_TIMEOUT_SECONDS", "30")))
            self._send_json(200, {"note": "客户端应先超时，此响应正常不可达"})
            return
        if scenario == "malformed":
            self._send_raw(200, '{"text": "被截断的'.encode("utf-8"))
            return

        # normal：按端点返回协议规定结构；语音端点校验 multipart 含文件字段。
        if kind == "transcription":
            if b'name="file"' not in body:
                self._send_json(400, {"error": {"message": "multipart 缺少 file 字段"}})
                return
            self._send_json(200, TRANSCRIPTION_OK)
        elif kind == "chat":
            self._send_json(200, CHAT_OK)
        else:
            self._send_json(200, MESSAGES_OK)


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenTypeless 模型协议模拟服务器")
    parser.add_argument("--port", type=int, default=8791)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), MockHandler)
    print(f"[mock] 监听 http://127.0.0.1:{args.port}/<scenario>/v1/... 场景：{sorted(SCENARIOS)}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
