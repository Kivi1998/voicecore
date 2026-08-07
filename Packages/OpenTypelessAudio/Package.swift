// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessAudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessAudio", targets: ["OpenTypelessAudio"])
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain")
    ],
    targets: [
        .target(
            name: "OpenTypelessAudio",
            dependencies: ["OpenTypelessDomain"]
        )
    ]
)
