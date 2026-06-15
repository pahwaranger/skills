import SwiftUI
#if SWIFT_PACKAGE
import Cache
import AppCore
import Installer
import DiffBridge
#endif

@main
struct SteveApp: App {
    // The composition root: wires OriginClient → Cache → StateEngine → CheckScheduler
    // → InstallEngine. Instantiated once at app launch; AppModel is passed into views
    // so they can read scheduler state for the menu-bar icon.

    /// Skills directory: where Claude Code loads skills from at runtime.
    private static let skillsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/skills", directoryHint: .isDirectory)

    /// Backups directory: where InstallEngine moves aside replaced skills (ADR 0007).
    private static let backupsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        return appSupport.appending(path: "Steve/backups", directoryHint: .isDirectory)
    }()

    /// Cache directory: shared between AppModel and InstallEngine.
    private static let cacheDirectory = AppModel.makeDefaultCacheRoot()

    private let appModel: AppModel = {
        let settings = SettingsStore()
        let engine = InstallEngine(
            skillsDirectory: SteveApp.skillsDirectory,
            backupsDirectory: SteveApp.backupsDirectory,
            cache: CacheStore(root: SteveApp.cacheDirectory)
        )
        return AppModel(
            owner: "pahwaranger",
            repo: "skills",
            branch: "master",
            transport: URLSessionTransport(),
            cacheRoot: SteveApp.cacheDirectory,
            interval: TimeInterval(settings.minutesBetweenChecks) * 60,
            automaticChecksEnabled: settings.automaticChecksEnabled,
            installEngine: engine
        )
    }()

    var body: some Scene {
        // Dynamic-label form: SwiftUI re-evaluates the label closure whenever any
        // @Observable property accessed inside it changes (isChecking, lastDerivedState).
        MenuBarExtra {
            DropdownView(appModel: appModel)
                .task {
                    await appModel.start()
                }
        } label: {
            let iconState = MenuBarIconState.from(
                derivedState: appModel.lastDerivedState,
                isChecking: appModel.isChecking
            )
            // Base colour: monochrome when idle, system red #FF3B30 when attention.
            // Pulsing modifier: overlaid in the current base colour while checking.
            let tint = iconState.attention
                ? Color(red: 1.0, green: 0.231, blue: 0.188)  // #FF3B30
                : Color.primary
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(tint)
                .symbolRenderingMode(.monochrome)
                .if(iconState.pulsing) { $0.symbolEffect(.pulse) }
        }
        .menuBarExtraStyle(.window)

        // Unified "Steve" window (Issue #45): a single window hosting both Review
        // and Settings as two tabs. Opened via `openWindow(id: "main")` from the
        // dropdown. The dropdown sets `appModel.selectedTab` (and `reviewFocusSkill`
        // for skill-row taps) before calling openWindow so the correct tab is shown.
        //
        // `.windowStyle(.hiddenTitleBar)`: the OS still draws the traffic-light buttons
        // but hides the default title bar text so `MainWindowView` can render its own
        // centered "Steve" label + two-tab chrome.
        Window("Steve", id: "main") {
            MainWindowView(appModel: appModel)
        }
        .defaultSize(width: 900, height: 640)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: — View+conditional modifier helper

private extension View {
    /// Applies `transform` only when `condition` is `true`.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
