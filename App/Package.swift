// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceCoreApp", targets: ["VoiceCoreApp"])
    ],
    dependencies: [
        .package(path: "../Packages/VoiceCoreDomain"),
        .package(path: "../Packages/VoiceCoreApplication"),
        .package(path: "../Packages/VoiceCoreData"),
        .package(path: "../Packages/VoiceCoreProviders"),
        .package(path: "../Packages/VoiceCorePlatform")
    ],
    targets: [
        .target(
            name: "VoiceCoreApp",
            dependencies: [
                "VoiceCoreDomain",
                "VoiceCoreApplication",
                "VoiceCoreData",
                "VoiceCoreProviders",
                "VoiceCorePlatform"
            ]
        )
    ]
)
