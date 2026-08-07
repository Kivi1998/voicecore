#!/usr/bin/env bash
# TEST-003 模拟服务器冒烟验证：逐场景断言状态码与响应结构，证明可重复复现。
# 用法：bash tools/mock_provider_smoke.sh
set -u

PORT=8791
BASE="http://127.0.0.1:${PORT}"
SERVER_LOG="$(mktemp -t mock_provider_server)"
FAILURES=0

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "${SERVER_PID}" 2>/dev/null
  rm -f "${SERVER_LOG}"
}
trap cleanup EXIT

python3 tools/mock_provider_server.py --port "${PORT}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!
sleep 1

check() { # check <名称> <期望状态码> <curl 额外参数...>
  local name="$1" expected="$2"
  shift 2
  local actual
  actual=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@")
  if [ "${actual}" = "${expected}" ]; then
    echo "通过  ${name} → ${actual}"
  else
    echo "失败  ${name} → 期望 ${expected} 实际 ${actual}"
    FAILURES=$((FAILURES + 1))
  fi
}

AUTH=(-H 'Authorization: Bearer sk-mock-smoke' -H 'x-api-key: sk-mock-smoke')
CHAT_BODY='{"model":"mock","messages":[{"role":"user","content":"hi"}]}'
ANTH_BODY='{"model":"mock","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}'
AUDIO_FIXTURE="$(mktemp -t mock_audio).m4a"
printf 'fake-audio-bytes' > "${AUDIO_FIXTURE}"
trap 'rm -f "${AUDIO_FIXTURE}"; cleanup' EXIT

for scenario in normal rate-limited auth-failed server-error malformed; do
  case "${scenario}" in
    normal) want=200 ;;
    rate-limited) want=429 ;;
    auth-failed) want=401 ;;
    server-error) want=500 ;;
    malformed) want=200 ;; # 状态码正常但响应非法，由解析方判错
  esac
  check "语音/${scenario}" "${want}" "${AUTH[@]}" -F "file=@${AUDIO_FIXTURE};type=audio/m4a" -F 'model=whisper-1' "${BASE}/${scenario}/v1/audio/transcriptions"
  check "改写-OpenAI/${scenario}" "${want}" "${AUTH[@]}" -H 'Content-Type: application/json' -d "${CHAT_BODY}" "${BASE}/${scenario}/v1/chat/completions"
  check "改写-Anthropic/${scenario}" "${want}" "${AUTH[@]}" -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -d "${ANTH_BODY}" "${BASE}/${scenario}/v1/messages"
done

# 超时场景：服务器挂起，客户端必须在 max-time 内超时（curl 退出码 28）。
curl -s -o /dev/null --max-time 3 "${AUTH[@]}" -H 'Content-Type: application/json' -d "${CHAT_BODY}" "${BASE}/timeout/v1/chat/completions"
if [ $? -eq 28 ]; then
  echo "通过  超时场景 → 客户端如期超时"
else
  echo "失败  超时场景 → 未按预期超时"
  FAILURES=$((FAILURES + 1))
fi

# 畸形响应：确认正文确实不是合法 JSON。
BODY=$(curl -s --max-time 5 "${AUTH[@]}" -H 'Content-Type: application/json' -d "${CHAT_BODY}" "${BASE}/malformed/v1/chat/completions")
if echo "${BODY}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  echo "失败  畸形场景 → 响应居然是合法 JSON"
  FAILURES=$((FAILURES + 1))
else
  echo "通过  畸形场景 → 响应非法 JSON，解析方将报解析错误"
fi

# multipart 缺文件字段应 400。
check "语音缺文件字段" 400 "${AUTH[@]}" -F 'model=whisper-1' "${BASE}/normal/v1/audio/transcriptions"

echo "---"
if [ "${FAILURES}" -eq 0 ]; then
  echo "冒烟验证全部通过"
else
  echo "冒烟验证存在 ${FAILURES} 项失败"
  exit 1
fi
