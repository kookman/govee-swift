// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoveeBLE",
    platforms: [
        .macOS(.v10_15)  // CoreBluetooth requires macOS 10.15+
    ],
    dependencies: [
        .package(url: "https://github.com/emqx/CocoaMQTT.git", from: "2.1.0")
    ],
    targets: [
        .executableTarget(
            name: "GoveeBLE",
            dependencies: ["CocoaMQTT"]),
    ]
)
