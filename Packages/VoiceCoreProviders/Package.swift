// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreProviders",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "VoiceCoreProviders", targets: ["VoiceCoreProviders"])
    ],
    dependencies: [
        .package(path: "../VoiceCoreDomain")
    ],
    targets: [
        .target(
            name: "VoiceCoreProviders",
            dependencies: ["VoiceCoreDomain"]
        ),
        .testTarget(
            name: "VoiceCoreProvidersTests",
            dependencies: ["VoiceCoreProviders"]
        )
    ]
)
