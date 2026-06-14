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
        .target(
            name: "OriginClient",
            dependencies: ["Cache"],
            path: "Sources/OriginClient"
        ),
        .target(
            name: "Scheduler",
            dependencies: ["StateEngine"],
            path: "Sources/Scheduler"
        ),
        .target(
            name: "Installer",
            dependencies: ["Cache"],
            path: "Sources/Installer"
        ),
        .target(
            name: "AppCore",
            dependencies: ["Cache", "StateEngine", "OriginClient", "Scheduler", "Installer", "DiffBridge"],
            path: "Sources/AppCore"
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
        .testTarget(
            name: "OriginClientTests",
            dependencies: ["OriginClient"],
            path: "SteveTests",
            sources: ["OriginClientTests.swift"]
        ),
        .testTarget(
            name: "SchedulerTests",
            dependencies: ["Scheduler"],
            path: "SteveTests",
            sources: ["SchedulerTests.swift"]
        ),
        .testTarget(
            name: "URLSessionTransportTests",
            dependencies: ["OriginClient"],
            path: "SteveTests",
            sources: ["URLSessionTransportTests.swift"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "Cache", "OriginClient", "StateEngine", "Scheduler"],
            path: "SteveTests",
            sources: ["AppCoreTests.swift"]
        ),
        .testTarget(
            name: "DropdownLogicTests",
            dependencies: ["AppCore", "StateEngine"],
            path: "SteveTests",
            sources: ["DropdownLogicTests.swift"]
        ),
        .testTarget(
            name: "ReviewSidebarTests",
            dependencies: ["AppCore", "StateEngine"],
            path: "SteveTests",
            sources: ["ReviewSidebarTests.swift"]
        ),
        .target(
            name: "DiffBridge",
            path: "Sources/DiffBridge"
        ),
        .testTarget(
            name: "InstallerTests",
            dependencies: ["Installer", "Cache"],
            path: "SteveTests",
            sources: ["InstallerTests.swift"]
        ),
        .testTarget(
            name: "DiffBridgeTests",
            dependencies: ["DiffBridge"],
            path: "SteveTests",
            sources: ["DiffBridgeTests.swift"]
        ),
        .testTarget(
            name: "UnifiedDiffParserTests",
            dependencies: ["DiffBridge"],
            path: "SteveTests",
            sources: ["UnifiedDiffParserTests.swift"]
        ),
        .testTarget(
            name: "ReviewSessionTests",
            dependencies: ["AppCore", "Cache", "OriginClient", "StateEngine", "Installer"],
            path: "SteveTests",
            sources: ["ReviewSessionTests.swift"]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["AppCore", "DiffBridge"],
            path: "SteveTests",
            sources: ["SettingsTests.swift"]
        ),
    ]
)
