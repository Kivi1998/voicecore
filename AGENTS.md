# Repository Guidelines

## Project Shape

Voicecore is a macOS menu bar voice input and translation app written in Swift with an Xcode project at `Voicecore.xcodeproj`.

- Main app sources live under `Voicecore/`.
- Tests live under `VoicecoreTests/`, with shared helpers in `VoicecoreTests/TestSupport/`.
- User-facing docs live under `docs/`.
- Local build products, derived data, and scratch references live under `build/` and `tmp/`; avoid editing or reviewing generated files there.
- The root `.codex/` directory is local workflow state and is gitignored.

## Build And Test

Use the shared `Voicecore` scheme.

```bash
xcodebuild -list -project Voicecore.xcodeproj
xcodebuild build -project Voicecore.xcodeproj -scheme Voicecore -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Voicecore.xcodeproj -scheme Voicecore -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

For focused test runs, prefer `-only-testing:VoicecoreTests/TestClassName` or `-only-testing:VoicecoreTests/TestClassName/testMethodName`.

CI runs tests with explicit SwiftPM cache paths and `CODE_SIGNING_ALLOWED=NO`; mirror `.github/workflows/tests.yml` when reproducing CI package resolution issues.

## Signing

Shared signing defaults are in `Config/Signing.shared.xcconfig`.
For local signing, copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`; the local file is gitignored. Do not commit personal signing settings.

## Coding Conventions

- Follow existing Swift style in nearby files.
- Keep UI work consistent with the existing SwiftUI/AppKit split under `Voicecore/UI`, `Voicecore/Settings`, and `Voicecore/App`.
- Prefer existing managers, stores, and support types before adding new abstractions.
- Keep tests deterministic by using `UserDefaults` suites and temporary directories from `VoicecoreTests/TestSupport` where applicable.
- Do not modify audio fixtures in `VoicecoreTests/Fixtures/Audio/` unless the task explicitly requires fixture changes.

## Dependencies

Swift package dependencies are resolved through the Xcode project. Notable packages include WhisperKit, MLXAudio, mlx-swift, mlx-swift-lm, Sparkle, SwiftSoup, and PermissionFlow. The MLX Audio dependency policy is documented in `docs/MLXAudioDependency.md`.

## Release Workflow

Release automation is in `.github/workflows/release.yml`. Stable release tasks may also use the local `voicecore-release` skill under `.codex/skills/voicecore-release/`.
