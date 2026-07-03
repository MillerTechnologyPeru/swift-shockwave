// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftShockwave",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ShockwaveFile", targets: ["ShockwaveFile"]),
        .library(name: "ShockwaveModel", targets: ["ShockwaveModel"]),
        .library(name: "ShockwavePlayer", targets: ["ShockwavePlayer"])
    ],
    dependencies: [
        .package(url: "https://github.com/MillerTechnologyPeru/swift-lingo", branch: "master"),
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
        .target(
            name: "ShockwaveModel",
            dependencies: [
                "ShockwaveFile",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoBytecode", package: "swift-lingo")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .target(
            name: "ShockwavePlayer",
            dependencies: [
                "ShockwaveFile", "ShockwaveModel",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoBytecode", package: "swift-lingo"),
                .product(name: "LingoVM", package: "swift-lingo")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .target(
            name: "ShockwaveTestSupport",
            path: "Tests/ShockwaveTestSupport",
            resources: [.copy("Resources")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "ShockwaveFileTests",
            dependencies: ["ShockwaveFile", "ShockwaveTestSupport"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "ShockwaveModelTests",
            dependencies: [
                "ShockwaveModel", "ShockwaveFile", "ShockwaveTestSupport",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoBytecode", package: "swift-lingo")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "ShockwavePlayerTests",
            dependencies: [
                "ShockwavePlayer", "ShockwaveModel", "ShockwaveFile", "ShockwaveTestSupport",
                .product(name: "LingoRuntime", package: "swift-lingo"),
                .product(name: "LingoVM", package: "swift-lingo")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        )
    ]
)
