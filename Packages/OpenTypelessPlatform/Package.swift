// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessPlatform",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessPlatform", targets: ["OpenTypelessPlatform"])
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain")
    ],
    targets: [
        .target(
            name: "OpenTypelessPlatform",
            dependencies: ["OpenTypelessDomain"]
        )
    ]
)
