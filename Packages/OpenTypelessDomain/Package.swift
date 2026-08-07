// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenTypelessDomain",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "OpenTypelessDomain", targets: ["OpenTypelessDomain"])
    ],
    targets: [
        .target(name: "OpenTypelessDomain"),
        .testTarget(
            name: "OpenTypelessDomainTests",
            dependencies: ["OpenTypelessDomain"]
        )
    ]
)
