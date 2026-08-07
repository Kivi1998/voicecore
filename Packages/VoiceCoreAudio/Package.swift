// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreAudio",
    platforms: [.macOS(.v14)],
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
        )
    ]
)
