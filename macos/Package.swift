// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cosmos",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CosmosCore", targets: ["CosmosCore"]),
        .executable(name: "cosmos", targets: ["CosmosCli"]),
        .executable(name: "cosmos-fixture-app", targets: ["CosmosFixtureApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .target(
            name: "PrivateApi",
            path: "Sources/PrivateApi",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CosmosCore",
            dependencies: [
                "PrivateApi",
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/CosmosCore"
        ),
        .executableTarget(
            name: "CosmosCli",
            dependencies: [
                "CosmosCore"
            ],
            path: "Sources/CosmosCli"
        ),
        .executableTarget(
            name: "CosmosFixtureApp",
            path: "Sources/CosmosFixtureApp"
        ),
        .testTarget(
            name: "CosmosCoreTests",
            dependencies: [
                "CosmosCore"
            ],
            path: "Tests/CosmosCoreTests"
        ),
        .testTarget(
            name: "CosmosCliTests",
            dependencies: [
                "CosmosCli"
            ],
            path: "Tests/CosmosCliTests"
        )
    ]
)
