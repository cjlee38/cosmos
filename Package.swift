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
    ],
    targets: [
        .target(
            name: "PrivateApi",
            path: "Sources/PrivateApi",
            publicHeadersPath: "include"
        ),
        .target(
            name: "KkaciCore",
            dependencies: ["PrivateApi"],
            path: "Sources/KkaciCore"
        ),
        .executableTarget(
            name: "KkaciCli",
            dependencies: ["KkaciCore"],
            path: "Sources/KkaciCli"
        ),
        .testTarget(
            name: "KkaciCoreTests",
            dependencies: ["KkaciCore"],
            path: "Tests/KkaciCoreTests"
        ),
    ]
)
