#!/bin/bash
set -euo pipefail

ARCHIVE_PATH="${1:-build/VoiceCore.xcarchive}"
OUTPUT_PATH="${2:-build/VoiceCore.dmg}"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/VoiceCore.app"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "未找到归档应用：${APP_PATH}" >&2
    echo "请先运行 make archive。" >&2
    exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/voicecore-dmg.XXXXXX")"
cleanup() {
    rm -rf "${STAGING_ROOT}"
}
trap cleanup EXIT

mkdir -p "${STAGING_ROOT}/VoiceCore"
ditto "${APP_PATH}" "${STAGING_ROOT}/VoiceCore/VoiceCore.app"
ln -s /Applications "${STAGING_ROOT}/VoiceCore/Applications"
mkdir -p "$(dirname "${OUTPUT_PATH}")"

hdiutil create \
    -volname VoiceCore \
    -srcfolder "${STAGING_ROOT}/VoiceCore" \
    -ov \
    -format UDZO \
    "${OUTPUT_PATH}"

echo "已生成 ${OUTPUT_PATH}"
