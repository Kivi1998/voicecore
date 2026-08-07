// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessApplication",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "OpenTypelessApplication", targets: ["OpenTypelessApplication"]),
    ],
    dependencies: [
        .package(path: "../OpenTypelessDomain"),
        .package(path: "../OpenTypelessData"),
    ],
    targets: [
        .target(
            name: "OpenTypelessApplication",
            dependencies: ["OpenTypelessDomain"]
        ),
        .testTarget(
            name: "OpenTypelessApplicationTests",
            dependencies: [
                "OpenTypelessApplication",
                "OpenTypelessDomain",
                "OpenTypelessData",
            ]
        ),
    ]
)
