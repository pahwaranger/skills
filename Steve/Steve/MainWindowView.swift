import SwiftUI
#if SWIFT_PACKAGE
import AppCore
#endif

// MARK: — Unified "Steve" window (Issue #45)

/// The content of the single "Steve" window that replaces the old "Review Skills"
/// and "Steve Settings" windows. Hosts a custom title + two-tab row at the top,
/// with `ReviewWindowView` and `SettingsView` as the two tab contents.
///
/// ## Chrome
/// The scene is declared with `.windowStyle(.hiddenTitleBar)` so the OS still
/// draws the traffic-light buttons while this view owns the centered title and
/// the tab row. The tab row uses `Color(light:dark:)` (from `Color+Theme.swift`)
/// to render the active-tab pill at the right opacity in both Aqua and Dark Aqua.
///
/// ## Lifecycle / review-session safety
/// `ReviewWindowView` calls `openReviewSession()` in `.onAppear` and
/// `closeReviewSession()` in `.onDisappear`. To avoid tearing down and
/// re-snapshotting the in-progress review session every time the user switches
/// to the Settings tab, we keep `ReviewWindowView` in the hierarchy at all times
/// and merely hide/show it using `.opacity` + `.allowsHitTesting`. This means
/// `onAppear` fires once (when the window first opens) and `onDisappear` fires
/// once (when the window closes), preserving the review session across tab switches.
struct MainWindowView: View {
    let appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom title + tab chrome ─────────────────────────────────
            WindowChromeView(appModel: appModel)

            Divider()

            // ── Tab content ───────────────────────────────────────────────
            // Both views remain in the hierarchy; only opacity / hit-testing changes.
            // This preserves the ReviewSession across tab switches (see lifecycle note above).
            ZStack(alignment: .top) {
                ReviewWindowView(appModel: appModel)
                    .opacity(appModel.selectedTab == .review ? 1 : 0)
                    .allowsHitTesting(appModel.selectedTab == .review)

                SettingsView()
                    .opacity(appModel.selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(appModel.selectedTab == .settings)
            }
        }
    }
}

// MARK: — Window chrome: centered title + tab row

/// The custom title bar chrome: a centered "Steve" label above a centered two-tab
/// row. Matches the locked design in `prototypes/review-diff/app/src/components/
/// WindowChrome.tsx` and `prototypes/settings/index.html`.
///
/// Active tab: subtle pill background + primary text colour.
/// Inactive tab: no background + secondary text colour.
private struct WindowChromeView: View {
    let appModel: AppModel

    var body: some View {
        VStack(spacing: 4) {
            // Centered "Steve" title
            Text("Steve")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 12)

            // Centered two-tab row
            HStack(spacing: 2) {
                TabButton(
                    title: "Review",
                    systemImage: "arrow.up.arrow.down",
                    isActive: appModel.selectedTab == .review
                ) {
                    appModel.selectedTab = .review
                }
                TabButton(
                    title: "Settings",
                    systemImage: "gear",
                    isActive: appModel.selectedTab == .settings
                ) {
                    appModel.selectedTab = .settings
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        // The chrome needs to be draggable (the user can drag the window by the title area).
        .background(WindowDragArea())
    }
}

// MARK: — Individual tab button

/// A stacked glyph-over-label tab button with an active-pill highlight.
///
/// Active pill: `rgba(0,0,0,0.07)` in light mode, `rgba(255,255,255,0.12)` in dark mode.
/// These values match the locked prototype chrome (WindowChrome.tsx).
private struct TabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    /// Active-tab pill colour: light rgba(0,0,0,0.07) / dark rgba(255,255,255,0.12).
    private var pillColor: Color {
        Color(
            light: Color.black.opacity(0.07),
            dark:  Color.white.opacity(0.12)
        )
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pillColor)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Window drag area

/// An invisible background that makes the chrome area draggable so the user can
/// move the window by clicking and dragging anywhere in the title / tab strip.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override var isOpaque: Bool { false }
    }
}
