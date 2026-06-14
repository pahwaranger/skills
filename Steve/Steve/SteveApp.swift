import SwiftUI

@main
struct SteveApp: App {
    // The composition root: wires OriginClient → Cache → StateEngine → CheckScheduler.
    // Instantiated once at app launch; AppModel is passed into views so they can
    // read scheduler state for the menu-bar icon.
    private let appModel = AppModel(
        owner: "pahwaranger",
        repo: "skills",
        branch: "master",
        transport: URLSessionTransport()
    )

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

        // Review window scene (Slice 8).
        // Opened via `openWindow(id: "review")` from the MenuBarExtra dropdown view.
        // The triggering skill is passed through `appModel.reviewFocusSkill` and
        // consumed by `ReviewWindowView.onAppear` / `onChange`.
        // Slices 9a/9b add the diff pane; Slice 10 wires Update/Skip.
        Window("Review Skills", id: "review") {
            ReviewWindowView(appModel: appModel)
        }
        .defaultSize(width: 900, height: 600)
        .defaultPosition(.center)
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
