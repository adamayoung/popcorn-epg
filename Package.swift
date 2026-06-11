// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PopcornEPG",

    platforms: [.macOS(.v13)],

    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/adamayoung/TMDb.git", from: "18.0.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0")
    ],

    targets: [
        .executableTarget(
            name: "PopcornEPG",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TMDb", package: "TMDb"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        )
    ]
)
