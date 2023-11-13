// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "portal-swap-sdk-swift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15)
    ],
    products: [
        .library(
            name: "PortalSwapSDK",
            targets: ["PortalSwapSDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/google/promises.git", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/cuhte3/web3swift", .upToNextMajor(from: "3.2.5")),
        .package(url: "https://github.com/vapor/websocket-kit", .upToNextMajor(from: "2.0.0"))
    ],
    targets: [
        .target(
            name: "PortalSwapSDK",
            dependencies: [
                .product(name: "Promises", package: "promises"),
                .product(name: "web3swift", package: "web3swift"),
                .product(name: "WebSocketKit", package: "websocket-kit")
            ]
        ),
        .testTarget(
            name: "PortalSwapSDKTests",
            dependencies: [
                "PortalSwapSDK",
                .product(name: "Promises", package: "promises"),
                .product(name: "web3swift", package: "web3swift"),
                .product(name: "WebSocketKit", package: "websocket-kit")
            ]
        ),
    ]
)
