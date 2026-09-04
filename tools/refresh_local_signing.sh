#!/usr/bin/env bash
# 定期重新构建 VoiceCore 并本地安装，用于刷新免费 Apple ID（Personal Team）
# 自动签名生成的 7 天有效期描述文件（provisioning profile），避免过期后
# 出现 "amfid: No matching profile found" 导致应用无法启动。
#
# 由 LaunchAgent com.kivi.voicecore.signing-refresh 定时调用，也可手动执行。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Voicecore.xcodeproj"
SCHEME="Voicecore"
CONFIGURATION="Release"
APP_NAME="VoiceCore"
DESTINATION="platform=macOS,arch=$(uname -m)"
DERIVED_DATA="$ROOT/build/SigningRefreshDerivedData"
INSTALL_DIR="/Applications"
LOG_DIR="$HOME/Library/Logs/VoiceCore"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "==> Building $SCHEME ($CONFIGURATION) to refresh Apple Development provisioning profile"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$APP_PATH" ]]; then
  log "error: built app not found at $APP_PATH"
  exit 1
fi

log "==> Verifying code signature"
if ! codesign --verify --strict --deep "$APP_PATH"; then
  log "error: codesign verification failed, aborting install"
  exit 1
fi

if [[ -f "$APP_PATH/Contents/embedded.provisionprofile" ]]; then
  PROFILE_PLIST="$(mktemp)"
  security cms -D -i "$APP_PATH/Contents/embedded.provisionprofile" -o "$PROFILE_PLIST" 2>/dev/null || true
  EXPIRATION="$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$PROFILE_PLIST" 2>/dev/null || echo "unknown")"
  rm -f "$PROFILE_PLIST"
  log "==> New provisioning profile expires: $EXPIRATION"
fi

log "==> Installing into $INSTALL_DIR"
WAS_RUNNING=false
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  WAS_RUNNING=true
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 1
  done
fi

rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1 || true

if [[ "$WAS_RUNNING" == "true" ]]; then
  log "==> Relaunching $APP_NAME (was running before refresh)"
  open "$INSTALL_DIR/$APP_NAME.app"
fi

log "==> Done."
