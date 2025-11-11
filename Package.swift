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
        .package(url: "https://github.com/cuhte3/Web3.swift.git", from: "0.8.10"),
        .package(url: "https://github.com/cuhte3/SwiftBTC", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/cuhte3/solana-swift.git", branch: "main")
    ],
    targets: [
        .target(
            name: "PortalSwapSDK",
            dependencies: [
                .product(name: "Promises", package: "promises"),
                .product(name: "Web3", package: "Web3.swift"),
                .product(name: "Web3PromiseKit", package: "Web3.swift"),
                .product(name: "Web3ContractABI", package: "Web3.swift"),
                .product(name: "SwiftBTC", package: "SwiftBTC"),
                .product(name : "SolanaSwift", package: "solana-swift")
            ]
        ),
        .testTarget(
            name: "PortalSwapSDKTests",
            dependencies: [
                "PortalSwapSDK",
                .product(name: "Promises", package: "promises"),
                .product(name: "Web3", package: "Web3.swift"),
                .product(name: "Web3PromiseKit", package: "Web3.swift"),
                .product(name: "Web3ContractABI", package: "Web3.swift"),
                .product(name: "SwiftBTC", package: "SwiftBTC"),
                .product(name: "SolanaSwift", package: "solana-swift")
            ]
        ),
    ]
)
