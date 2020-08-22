// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KSSModbus",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "KSSModbus", targets: ["KSSModbus"]),
    ],
    dependencies: [
        .package(url: "https://github.com/klassen-software-solutions/KSSCore.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
    ],
    targets: [
        .target(name: "CModbus", dependencies: []),
        .target(name: "KSSModbus", dependencies: ["CModbus",
                                                  .product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "KSSModbusTests", dependencies: ["KSSModbus",
                                                           .product(name: "KSSTest", package: "KSSCore")]),
    ]
)
