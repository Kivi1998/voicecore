// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCorePlatform",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceCorePlatform", targets: ["VoiceCorePlatform"])
    ],
    dependencies: [
        .package(path: "../VoiceCoreDomain")
    ],
    targets: [
        .target(
            name: "VoiceCorePlatform",
            dependencies: ["VoiceCoreDomain"]
        ),
        .testTarget(
            name: "VoiceCorePlatformTests",
            dependencies: ["VoiceCorePlatform"]
        )
    ]
)
