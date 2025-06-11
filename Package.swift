// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RemoteImage",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "RemoteImage",
            targets: ["RemoteImage"]),
    ],
    targets: [
        .target(
            name: "RemoteImage"),
        .testTarget(
            name: "RemoteImageTests",
            dependencies: ["RemoteImage"]
        ),
    ]
)
