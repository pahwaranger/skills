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
        .target(
            name: "StateEngine",
            path: "Sources/StateEngine"
        ),
        .testTarget(
            name: "CacheTests",
            dependencies: ["Cache"],
            path: "SteveTests",
            sources: ["CacheTests.swift"]
        ),
        .testTarget(
            name: "StateEngineTests",
            dependencies: ["StateEngine"],
            path: "SteveTests",
            sources: ["StateEngineTests.swift"]
        ),
    ]
)
