// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Clarion",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Clarion",
            path: "Sources/Clarion"
        )
    ]
)
