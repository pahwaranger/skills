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
        // FixtureEngine: non-test library for fixture mode (ADR 0009).
        // Depends on OriginClient (for TarballExtractor re-export) and StateEngine
        // (for SkillState in FixtureScenario). AppCore depends on this so
        // AppModel.fixtureMode(_:) is reachable from the production app layer.
        .target(
            name: "FixtureEngine",
            dependencies: ["Cache", "StateEngine", "OriginClient"],
            path: "Sources/FixtureEngine"
        ),
        .target(
            name: "AppCore",
            dependencies: ["Cache", "StateEngine", "OriginClient", "Scheduler", "Installer", "DiffBridge", "FixtureEngine"],
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
            dependencies: ["AppCore", "Cache", "OriginClient", "StateEngine", "Scheduler", "FixtureEngine"],
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
        .testTarget(
            name: "DiffPaneHelpersTests",
            dependencies: ["AppCore", "StateEngine"],
            path: "SteveTests",
            sources: ["DiffPaneHelpersTests.swift"]
        ),
        .target(
            name: "DiffBridge",
            dependencies: ["Theme"],
            path: "Sources/DiffBridge"
        ),
        .target(
            name: "Theme",
            path: "Sources/Theme"
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
            name: "UnifiedDiffGeneratorTests",
            dependencies: ["DiffBridge"],
            path: "SteveTests",
            sources: ["UnifiedDiffGeneratorTests.swift"]
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
        .testTarget(
            name: "ThemeTests",
            dependencies: ["Theme"],
            path: "SteveTests",
            sources: ["ThemeTests.swift"]
        ),
        .testTarget(
            name: "FileDiffStatusMappingTests",
            dependencies: ["DiffBridge", "Theme"],
            path: "SteveTests",
            sources: ["FileDiffStatusMappingTests.swift"]
        ),
        // FixtureEngine tests: cover FixtureScenario, FixtureMode, MultiSkillTarball,
        // and AppModel.fixtureMode(_:).
        .testTarget(
            name: "FixtureEngineTests",
            dependencies: ["AppCore", "FixtureEngine", "StateEngine", "OriginClient"],
            path: "SteveTests",
            sources: ["FixtureEngineTests.swift"]
        ),
        // F2 tests: installed-files provider defaulting and injection (Issue #72).
        .testTarget(
            name: "InstalledFilesProviderTests",
            dependencies: ["AppCore", "FixtureEngine", "StateEngine"],
            path: "SteveTests",
            sources: ["InstalledFilesProviderTests.swift"]
        ),
    ]
)
