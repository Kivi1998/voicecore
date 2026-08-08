#!/usr/bin/env bash

set -euo pipefail

ROOT="/Users/guanwei/x/doit/Voicecore"
PROJECT="$ROOT/Voicecore.xcodeproj"
SCHEME="Voicecore"
CONFIGURATION="TestDebug"
DESTINATION="platform=macOS"
SPM_CACHE_PATH="${VOICECORE_SPM_CACHE_PATH:-$ROOT/tmp/regression/spm-cache}"
SPM_CLONE_PATH="${VOICECORE_SPM_CLONE_PATH:-$ROOT/tmp/regression/spm-source-packages}"

if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "Local regression matrix is intended for local machines only." >&2
  exit 1
fi

GROUP="${1:-all}"

run_tests() {
  local label="$1"
  shift
  echo
  echo "==> Running $label"
  if model_tests_enabled; then
    run_tests_with_model_gate "$label" "$@"
  else
    mkdir -p "$SPM_CACHE_PATH" "$SPM_CLONE_PATH"
    xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -clonedSourcePackagesDirPath "$SPM_CLONE_PATH" \
      -packageCachePath "$SPM_CACHE_PATH" \
      "$@"
  fi
}

model_tests_enabled() {
  case "${VOICECORE_RUN_MODEL_TESTS:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

plist_set_or_add() {
  local plist="$1"
  local key_path="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Set $key_path $value" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add $key_path string $value" "$plist"
}

run_tests_with_model_gate() {
  local label="$1"
  shift
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local derived_data="$ROOT/tmp/regression/model-derived-$stamp"
  rm -rf "$derived_data"
  mkdir -p "$SPM_CACHE_PATH" "$SPM_CLONE_PATH"

  echo "==> Building test products for $label with VOICECORE_RUN_MODEL_TESTS=1"
  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data" \
    -clonedSourcePackagesDirPath "$SPM_CLONE_PATH" \
    -packageCachePath "$SPM_CACHE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    "$@"

  local xctestrun
  xctestrun="$(find "$derived_data/Build/Products" -name '*.xctestrun' -print -quit)"
  if [[ -z "$xctestrun" ]]; then
    echo "Could not find .xctestrun under $derived_data/Build/Products" >&2
    return 1
  fi

  plist_set_or_add "$xctestrun" ":VoicecoreTests:EnvironmentVariables:VOICECORE_RUN_MODEL_TESTS" "1"
  plist_set_or_add "$xctestrun" ":VoicecoreTests:TestingEnvironmentVariables:VOICECORE_RUN_MODEL_TESTS" "1"

  echo "==> Running $label from $xctestrun"
  xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "$DESTINATION" \
    "$@"
}

run_group_collecting_failures() {
  local overall=0
  local labels=()
  while [[ "$#" -gt 0 ]]; do
    local group_name="$1"
    shift
    labels+=("$group_name")
    set +e
    "$group_name"
    local status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      overall=$status
      echo
      echo "!! Group failed: $group_name (exit $status)"
    fi
  done

  if [[ $overall -ne 0 ]]; then
    echo
    echo "Completed with failures across groups: ${labels[*]}"
    return "$overall"
  fi
}

run_core() {
  run_tests "core pipeline/runtime regression" \
    -only-testing:VoicecoreTests/TranscriptionCapturePipelineTests \
    -only-testing:VoicecoreTests/SessionTimingSummarySupportTests \
    -only-testing:VoicecoreTests/SessionTextIOTests \
    -only-testing:VoicecoreTests/SessionEndFlowTests \
    -only-testing:VoicecoreTests/LLMExecutionPlanCompilerTests \
    -only-testing:VoicecoreTests/EnhancementPromptResolverTests \
    -only-testing:VoicecoreTests/PromptBuildersTests \
    -only-testing:VoicecoreTests/AppPromptDefaultsTests \
    -only-testing:VoicecoreTests/ASRVoiceActivityPlanningTests \
    -only-testing:VoicecoreTests/FeatureSettingsStoreTests \
    -only-testing:VoicecoreTests/MLXTranscriptionPlanningTests \
    -only-testing:VoicecoreTests/ModelDebugSupportTests
}

run_mlx() {
  run_tests "MLX public fixture regression" \
    -only-testing:VoicecoreTests/QwenOfficialFixtureASRIntegrationTests \
    -only-testing:VoicecoreTests/MLXLongFormReplayIntegrationTests \
    -only-testing:VoicecoreTests/MLXFinalOnlyReplayIntegrationTests \
    -only-testing:VoicecoreTests/MLXRealtimeReplayIntegrationTests \
    -only-testing:VoicecoreTests/MLXPipelineMetricsIntegrationTests
}

run_gguf() {
  run_tests_with_model_gate "GGUF native termination regression" \
    -only-testing:VoicecoreTests/GGUFUTF8OutputAccumulatorTests/testInstalledGGUFModelIsExplicitlyReleasedDuringApplicationTermination
}

run_vad() {
  run_tests "local VAD planning regression" \
    -only-testing:VoicecoreTests/ASRVoiceActivityPlanningTests \
    -only-testing:VoicecoreTests/FeatureSettingsStoreTests \
    -only-testing:VoicecoreTests/ModelDebugSupportTests
}

run_whisper() {
  run_tests "Whisper diagnostic regression" \
    -only-testing:VoicecoreTests/WhisperOfficialFixtureASRIntegrationTests \
    -only-testing:VoicecoreTests/WhisperLongFormReplayIntegrationTests \
    -only-testing:VoicecoreTests/WhisperRealtimeReplayIntegrationTests \
    -only-testing:VoicecoreTests/WhisperPipelineMetricsIntegrationTests
}

run_installed_matrix() {
  run_tests "installed-model long-form matrix" \
    -only-testing:VoicecoreTests/InstalledASRLongFormMatrixIntegrationTests
}

case "$GROUP" in
  core)
    run_core
    ;;
  mlx)
    run_mlx
    ;;
  gguf)
    run_gguf
    ;;
  vad)
    run_vad
    ;;
  whisper)
    run_whisper
    ;;
  installed)
    run_installed_matrix
    ;;
  diagnostic)
    run_group_collecting_failures run_whisper run_installed_matrix
    ;;
  all)
    run_core
    run_mlx
    run_vad
    ;;
  full)
    run_group_collecting_failures run_core run_mlx run_gguf run_vad run_whisper run_installed_matrix
    ;;
  *)
    echo "Unknown group: $GROUP" >&2
    echo "Usage: $0 [core|mlx|gguf|vad|whisper|installed|diagnostic|all|full]" >&2
    exit 2
    ;;
esac
