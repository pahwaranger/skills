import SwiftUI
#if SWIFT_PACKAGE
import Cache
import AppCore
import Installer
import DiffBridge
import FixtureEngine
#endif

@main
struct SteveApp: App {
    // The composition root: wires OriginClient → Cache → StateEngine → CheckScheduler
    // → InstallEngine. Instantiated once at app launch; AppModel is passed into views
    // so they can read scheduler state for the menu-bar icon.
    //
    // In fixture mode (`--fixtures` arg or `STEVE_FIXTURES=1` env var), composition
    // routes through `AppModel.fixtureMode(scenario:)` instead and the real Skills
    // dir is never touched (ADR 0009).

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

    // MARK: — Composition root

    /// The composed AppModel and installed-files provider for the diff pane.
    /// Both are derived from the same sandbox in fixture mode so state and diff agree.
    private let appModel: AppModel
    private let installedFilesProvider: (String) -> [String: Data]

    init() {
        if FixtureMode.isActive {
            // Fixture mode: compose via AppModel.fixtureMode(scenario:).
            // App initialisation runs on the main thread, so assumeIsolated is safe.
            // Only extract the Sendable parts (AppModel, URL) from the tuple;
            // discard fixtureDefaults (UserDefaults is not Sendable) inside the closure.
            let (model, sandboxSkillsDir): (AppModel, URL) = MainActor.assumeIsolated {
                let (m, dir, _) = AppModel.fixtureMode(scenario: .default)
                return (m, dir)
            }
            appModel = model
            // Build the installed-files provider from the SAME sandboxSkillsDir so
            // the state (hash provider built inside fixtureMode) and the diff (this
            // provider) both read from the same sandbox tree.
            installedFilesProvider = makeInstalledFilesProvider(skillsDir: sandboxSkillsDir)
        } else {
            // Production path — byte-for-byte unchanged (ADR 0009).
            let settings = SettingsStore()
            let engine = InstallEngine(
                skillsDirectory: SteveApp.skillsDirectory,
                backupsDirectory: SteveApp.backupsDirectory,
                cache: CacheStore(root: SteveApp.cacheDirectory)
            )
            appModel = AppModel(
                owner: "pahwaranger",
                repo: "skills",
                branch: "master",
                transport: URLSessionTransport(),
                cacheRoot: SteveApp.cacheDirectory,
                interval: TimeInterval(settings.minutesBetweenChecks) * 60,
                automaticChecksEnabled: settings.automaticChecksEnabled,
                installEngine: engine
            )
            installedFilesProvider = ReviewWindowView.defaultInstalledFilesProvider
        }
    }

    var body: some Scene {
        // Dynamic-label form: SwiftUI re-evaluates the label closure whenever any
        // @Observable property accessed inside it changes (isChecking, lastDerivedState).
        MenuBarExtra {
            DropdownView(appModel: appModel)
                .task {
                    await appModel.start()
                }
                // In fixture mode: auto-open the Steve window on the Review tab with
                // `diagnose` pre-selected immediately after the app starts.
                .fixtureAutoOpen(appModel: appModel, enabled: FixtureMode.isActive)
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
            MainWindowView(appModel: appModel, installedFilesProvider: installedFilesProvider)
                // In fixture mode (XCUITest): start the app model and pre-arm the review tab
                // directly from the window content, since the dropdown is never opened.
                // In production this is a no-op (.task only fires when FixtureMode.isActive).
                .task(id: FixtureMode.isActive) {
                    guard FixtureMode.isActive else { return }
                    appModel.selectedTab = .review
                    appModel.reviewFocusSkill = "diagnose"
                    await appModel.start()
                    // After the fixture check completes, open the review session so the
                    // diff pane can compute installed-vs-origin diffs (the SHA and skill
                    // files are now available from the completed check).
                    appModel.openReviewSession()
                }
        }
        .defaultSize(width: 900, height: 640)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        // In fixture mode (XCUITest): present the window automatically at launch so
        // XCUITest can find it without needing to click the menu-bar item first.
        .defaultLaunchBehavior(FixtureMode.isActive ? .presented : .suppressed)
    }

}

// MARK: — Fixture auto-open modifier

private extension View {
    /// In fixture mode only: auto-opens the Steve window on the Review tab with
    /// `diagnose` pre-selected as soon as this view appears.
    ///
    /// The `.task` that calls `appModel.start()` sets up the fixture pipeline;
    /// this modifier fires once on appear and drives the window open via the
    /// SwiftUI environment action so the Review tab is immediately visible.
    ///
    /// For `LSUIElement` apps (no Dock icon) the window does not activate
    /// automatically — `NSApp.activate(ignoringOtherApps: true)` is called
    /// explicitly so the window comes to the foreground.
    @ViewBuilder
    func fixtureAutoOpen(appModel: AppModel, enabled: Bool) -> some View {
        if enabled {
            self.modifier(FixtureAutoOpenModifier(appModel: appModel))
        } else {
            self
        }
    }
}

private struct FixtureAutoOpenModifier: ViewModifier {
    let appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Pre-arm the tab and focus skill, then open the window.
                // The review session populates naturally after the launch check completes
                // (ReviewWindowView.onAppear calls openReviewSession()).
                appModel.selectedTab = .review
                appModel.reviewFocusSkill = "diagnose"
                openWindow(id: "main")
                // LSUIElement apps don't activate automatically when a programmatic
                // window open fires — activate explicitly so the window surfaces.
                NSApp.activate(ignoringOtherApps: true)
            }
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
