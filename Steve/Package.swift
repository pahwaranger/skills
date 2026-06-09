// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Steve",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "Cache",
            path: "Sources/Cache"
        ),
        .testTarget(
            name: "CacheTests",
            dependencies: ["Cache"],
            path: "SteveTests",
            sources: ["CacheTests.swift"]
        ),
    ]
)
