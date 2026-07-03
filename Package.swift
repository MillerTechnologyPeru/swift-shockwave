// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftShockwave",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ShockwaveFile", targets: ["ShockwaveFile"])
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
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        )
    ]
)
