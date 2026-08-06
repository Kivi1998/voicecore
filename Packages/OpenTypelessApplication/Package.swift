// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessApplication",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessApplication", targets: ["OpenTypelessApplication"]),
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain"),
    ],
    targets: [
        .target(
            name: "OpenTypelessApplication",
            dependencies: ["OpenTypelessDomain"]
        ),
    ]
)
