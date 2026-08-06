// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessData",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenTypelessData", targets: ["OpenTypelessData"]),
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain"),
    ],
    targets: [
        .target(
            name: "OpenTypelessData",
            dependencies: ["OpenTypelessDomain"]
        ),
    ]
)
