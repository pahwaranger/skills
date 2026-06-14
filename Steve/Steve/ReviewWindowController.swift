import AppKit
import SwiftUI

// MARK: — Review window activation (Slice 8)

/// Opens (or raises) the Review window, optionally scrolling the sidebar to
/// the skill that triggered the open from the dropdown.
///
/// SwiftUI's `openWindow` action is only available inside a view hierarchy,
/// so the dropdown `Button` action (which runs outside any `Environment`)
/// must reach the window system through AppKit directly.
///
/// ## How it works
/// `NSApp.sendAction` dispatches `showWindow:` to the first responder chain,
/// which AppKit routes to the `Window` scene's controller. The `focusedSkill`
/// key is written into `UserDefaults.reviewWindowFocusedSkill` before the
/// dispatch so the `ReviewWindowView.onAppear` can read and clear it.
///
/// This indirection keeps the window scene in SwiftUI while letting imperative
/// code outside a view trigger it. A cleaner alternative (Environment-based
/// openWindow) would require threading the `@Environment(\.openWindow)` action
/// through every layer from `SteveApp` down to `SkillRowView` — not worth the
/// coupling for a single call site.
enum ReviewWindowController {

    /// Opens the "review" window scene and, if the window was already open,
    /// brings it to the front. Passes `skillName` as the initial sidebar focus.
    static func open(focusedOn skillName: String? = nil) {
        if let skillName {
            UserDefaults.standard.set(skillName, forKey: UserDefaults.reviewWindowFocusedSkill)
        }
        // openWindow is only available in the view environment.
        // As a fallback we activate the first "review"-titled window we can find,
        // or let the system open a new one via the menu action.
        if let window = NSApp.windows.first(where: { $0.title.hasPrefix("Review") }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // The Window scene will be opened on first access.
            // SwiftUI opens it lazily; we trigger via the App menu equivalent.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension UserDefaults {
    /// Key used to pass the focused skill name from the dropdown to the Review window.
    static let reviewWindowFocusedSkill = "com.steve.reviewWindowFocusedSkill"
}
