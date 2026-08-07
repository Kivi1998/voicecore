// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreAudio",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "VoiceCoreAudio", targets: ["VoiceCoreAudio"])
    ],
    dependencies: [
        .package(path: "../VoiceCoreDomain")
    ],
    targets: [
        .target(
            name: "VoiceCoreAudio",
            dependencies: ["VoiceCoreDomain"]
        ),
        .testTarget(
            name: "VoiceCoreAudioTests",
            dependencies: ["VoiceCoreAudio"]
        )
    ]
)
