// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCoreData",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "VoiceCoreData", targets: ["VoiceCoreData"])
    ],
    dependencies: [
        .package(path: "../VoiceCoreDomain"),
        // GRDB：SQLite 访问、事务、查询与迁移。许可证：MIT。
        // 选择理由：docs/DECISIONS.md D-017 已确认；锁定精确版本保证可复现。
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "VoiceCoreData",
            dependencies: [
                "VoiceCoreDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "VoiceCoreDataTests",
            dependencies: ["VoiceCoreData"]
        )
    ]
)
