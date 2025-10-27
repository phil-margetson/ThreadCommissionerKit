// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ThreadCommissionerKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ThreadCommissionerKit",
            targets: ["ThreadCommissionerKit"]
        ),
    ],
    targets: [
        // Binary target for mbedTLS xcframework
        .binaryTarget(
            name: "mbedTLS",
            path: "Frameworks/mbedTLS.xcframework"
        ),

        // C wrapper target exposing mbedTLS headers to Swift
        .target(
            name: "CThreadCommissioner",
            dependencies: ["mbedTLS"],
            path: "Sources/CThreadCommissioner",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Frameworks/mbedTLS.xcframework/ios-arm64/Headers"),
                .headerSearchPath("../../Frameworks/mbedTLS.xcframework/ios-arm64_x86_64-simulator/Headers")
            ]
        ),

        // Main library target
        .target(
            name: "ThreadCommissionerKit",
            dependencies: ["CThreadCommissioner", "mbedTLS"],
            path: "Sources/ThreadCommissionerKit",
            cSettings: [
                .headerSearchPath("../../Frameworks/mbedTLS.xcframework/ios-arm64/Headers"),
                .headerSearchPath("../../Frameworks/mbedTLS.xcframework/ios-arm64_x86_64-simulator/Headers")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),

        .testTarget(
            name: "ThreadCommissionerKitTests",
            dependencies: ["ThreadCommissionerKit"],
            path: "Tests/ThreadCommissionerKitTests"
        ),
    ]
)
