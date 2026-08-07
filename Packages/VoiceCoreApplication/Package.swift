// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreApplication",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "VoiceCoreApplication", targets: ["VoiceCoreApplication"])
    ],
    dependencies: [
        .package(path: "../VoiceCoreDomain"),
        .package(path: "../VoiceCoreData")
    ],
    targets: [
        .target(
            name: "VoiceCoreApplication",
            dependencies: ["VoiceCoreDomain"]
        ),
        .testTarget(
            name: "VoiceCoreApplicationTests",
            dependencies: [
                "VoiceCoreApplication",
                "VoiceCoreDomain",
                "VoiceCoreData"
            ]
        )
    ]
)
