// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "kkaci",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KkaciCore", targets: ["KkaciCore"]),
        .executable(name: "kkaci", targets: ["KkaciCli"]),
        .executable(name: "kkaci-app", targets: ["KkaciApp"]),
        .executable(name: "kkaci-fixture-app", targets: ["KkaciFixtureApp"])
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
            name: "KkaciCore",
            dependencies: [
                "PrivateApi",
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/KkaciCore"
        ),
        .executableTarget(
            name: "KkaciCli",
            dependencies: [
                "KkaciCore"
            ],
            path: "Sources/KkaciCli"
        ),
        .executableTarget(
            name: "KkaciApp",
            dependencies: [
                "KkaciCore"
            ],
            path: "Sources/KkaciApp"
        ),
        .executableTarget(
            name: "KkaciFixtureApp",
            path: "Sources/KkaciFixtureApp"
        ),
        .testTarget(
            name: "KkaciCoreTests",
            dependencies: [
                "KkaciCore"
            ],
            path: "Tests/KkaciCoreTests"
        ),
        .testTarget(
            name: "KkaciAppTests",
            dependencies: [
                "KkaciApp",
                "KkaciCore"
            ],
            path: "Tests/KkaciAppTests"
        )
    ]
)
