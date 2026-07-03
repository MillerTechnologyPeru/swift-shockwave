// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftShockwave",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ShockwaveFile", targets: ["ShockwaveFile"]),
        .library(name: "ShockwaveModel", targets: ["ShockwaveModel"])
    ],
    dependencies: [
        .package(url: "https://github.com/MillerTechnologyPeru/swift-lingo", from: "0.2.1"),
        .package(url: "https://github.com/apple/swift-binary-parsing", from: "0.0.1")
    ],
    targets: [
        .target(
            name: "ShockwaveFile",
            dependencies: [
                .product(name: "LingoBytecode", package: "swift-lingo"),
                .product(name: "BinaryParsing", package: "swift-binary-parsing")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "ShockwaveFileTests",
            dependencies: ["ShockwaveFile"],
            resources: [.copy("Resources")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .target(
            name: "ShockwaveModel",
            dependencies: [
                "ShockwaveFile",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoBytecode", package: "swift-lingo")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "ShockwaveModelTests",
            dependencies: [
                "ShockwaveModel", "ShockwaveFile",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoBytecode", package: "swift-lingo")
            ],
            resources: [.copy("Resources")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        )
    ]
)
