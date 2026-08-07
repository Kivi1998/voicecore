// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreDomain",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "VoiceCoreDomain", targets: ["VoiceCoreDomain"])
    ],
    targets: [
        .target(name: "VoiceCoreDomain"),
        .testTarget(
            name: "VoiceCoreDomainTests",
            dependencies: ["VoiceCoreDomain"]
        )
    ]
)
