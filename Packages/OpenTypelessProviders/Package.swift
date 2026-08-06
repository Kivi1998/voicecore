// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessProviders",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessProviders", targets: ["OpenTypelessProviders"]),
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain"),
    ],
    targets: [
        .target(
            name: "OpenTypelessProviders",
            dependencies: ["OpenTypelessDomain"]
        ),
    ]
)
