Third-Party Licenses
====================

VoiceCore is built on the following third-party libraries, fetched as
Swift Package Manager dependencies unless noted otherwise. Each package
retains its own copyright and license; the full license text for each
package is included in its own source distribution (visible in Xcode
under Project Navigator > Package Dependencies, or at the repository URL
below) and is not reproduced here in full.

No GPL, AGPL, LGPL, or non-commercial (e.g. CC-BY-NC) licensed dependency
is used anywhere in this project.

This project's own source is also, in substantial part, a derivative
work of Voxt (https://github.com/hehehai/voxt), which was itself
provided under the Apache License 2.0. See VOXT-APACHE-2.0.txt in this
directory and NOTICE in the repository root for the required upstream
attribution.

Swift Package dependencies
---------------------------

| Package         | Repository                              | License          |
|-----------------|------------------------------------------|------------------|
| EventSource     | mattt/EventSource                        | MIT              |
| llama.swift     | mattt/llama.swift                        | MIT              |
| swift-crypto    | apple/swift-crypto                       | Apache-2.0       |
| PermissionFlow  | jaywcjlove/PermissionFlow                 | MIT              |
| swift-log       | apple/swift-log                          | Apache-2.0       |
| swift-syntax    | apple/swift-syntax                       | Apache-2.0       |
| swift-numerics  | apple/swift-numerics                     | Apache-2.0       |
| swift-jinja     | huggingface/swift-jinja                  | Apache-2.0       |
| swift-collections | apple/swift-collections                | Apache-2.0       |
| FluidAudio      | FluidInference/FluidAudio                 | Apache-2.0       |
| MLXAudio        | Blaizzy/mlx-audio-swift (voice-activity detection only)  | MIT |
| swift-nio       | apple/swift-nio                          | Apache-2.0       |
| swift-atomics   | apple/swift-atomics                       | Apache-2.0       |
| mlx-swift       | ml-explore/mlx-swift                     | MIT              |
| GRDB            | groue/GRDB.swift                         | MIT              |
| Sparkle         | sparkle-project/Sparkle                   | BSD-style (+ bundled bsdiff/BSD-2, sais-lite/MIT, ed25519/zlib-style) |
| SwiftSoup       | scinfu/SwiftSoup                          | MIT              |
| swift-asn1      | apple/swift-asn1                         | Apache-2.0       |
| mlx-swift-lm    | ml-explore/mlx-swift-lm                   | MIT              |
| swift-transformers | huggingface/swift-transformers          | Apache-2.0       |
| swift-huggingface | huggingface/swift-huggingface           | Apache-2.0       |
| swift-system    | apple/swift-system                        | Apache-2.0       |
| FaviconFinder   | will-lumley/FaviconFinder                 | MIT              |
| yyjson          | ibireme/yyjson                            | MIT              |

Bundled compiled binaries
--------------------------

| Component                          | Source                                    | License          |
|-------------------------------------|--------------------------------------------|------------------|
| Voicecore/Frameworks/libomnivad.dylib | lifeiteng/OmniVAD-Kit (built via tools/build_omnivad_runtime.sh) | Apache License 2.0 — full text in Voicecore/Resources/OmniVAD/LICENSE-OmniVAD-Kit.txt |

Machine learning models
-------------------------

VoiceCore downloads local text-generation and speaker-analysis models on
demand at runtime (not bundled in the installer). Transcription itself
always uses a remote API provider configured by the user; there is no
on-device speech-recognition model download path. Local models are
sourced from Hugging Face, ModelScope, and GitHub Releases and each
carries its own upstream license (commonly Apache-2.0, MIT, or CC-BY-4.0
depending on the model family). Users who enable local model downloads
are responsible for reviewing the license of the specific model they
choose to download, including any custom Hugging Face repository entered
manually in Settings.
