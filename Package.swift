// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "kkaci",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "KkaciCore", targets: ["KkaciCore"]),
        .executable(name: "kkaci", targets: ["KkaciCli"]),
        .executable(name: "kkaci-app", targets: ["KkaciApp"]),
        .executable(name: "kkaci-fixture-app", targets: ["KkaciFixtureApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/soffes/HotKey.git", exact: "0.2.1"),
    ],
    targets: [
        .target(
            name: "PrivateApi",
            path: "Sources/PrivateApi",
            publicHeadersPath: "include"
        ),
        .target(
            name: "KkaciCore",
            dependencies: [
                "PrivateApi",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/KkaciCore"
        ),
        .executableTarget(
            name: "KkaciCli",
            dependencies: ["KkaciCore"],
            path: "Sources/KkaciCli"
        ),
        .executableTarget(
            name: "KkaciApp",
            dependencies: [
                "KkaciCore",
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources/KkaciApp"
        ),
        .executableTarget(
            name: "KkaciFixtureApp",
            path: "Sources/KkaciFixtureApp"
        ),
        .testTarget(
            name: "KkaciCoreTests",
            dependencies: ["KkaciCore"],
            path: "Tests/KkaciCoreTests"
        ),
    ]
)
