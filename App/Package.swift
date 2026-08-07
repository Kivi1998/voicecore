// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessApp", targets: ["OpenTypelessApp"])
    ],
    dependencies: [
        .package(path: "../Packages/OpenTypelessDomain"),
        .package(path: "../Packages/OpenTypelessApplication"),
        .package(path: "../Packages/OpenTypelessData"),
        .package(path: "../Packages/OpenTypelessProviders"),
        .package(path: "../Packages/OpenTypelessPlatform")
    ],
    targets: [
        .target(
            name: "OpenTypelessApp",
            dependencies: [
                "OpenTypelessDomain",
                "OpenTypelessApplication",
                "OpenTypelessData",
                "OpenTypelessProviders",
                "OpenTypelessPlatform"
            ]
        )
    ]
)
