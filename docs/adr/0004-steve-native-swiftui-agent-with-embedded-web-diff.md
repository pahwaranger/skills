# Steve is a native SwiftUI menu-bar agent with an embedded web view for diffs

Steve is built as a native macOS **SwiftUI** menu-bar agent (`LSUIElement`, no
Dock tile; login item via `SMAppService`), but its multi-skill **diff review**
surface is rendered with a web diff library inside an embedded `WKWebView` rather
than hand-built in AppKit/SwiftUI.

The native shell keeps an always-resident background agent genuinely lightweight
and gives first-class menu-bar / login-item / no-Dock behaviour for free. The one
hard part — a GitHub-PR-style split/unified, multi-file directory diff — is where
mature web libraries vastly outpace anything we'd hand-roll natively, so we host
just that surface in a web view. We rejected a fully web-based shell (Electron/
Tauri) because a heavyweight runtime for a tiny always-on agent isn't worth it,
and a fully native diff renderer because rebuilding PR-grade diff UI is not.

## Consequences

- **diff2html** is the chosen web diff library (confirmed by the Review-tab
  prototype; Monaco was the other candidate and was not needed). A diff2html
  dependency and a JS↔Swift bridge live inside an otherwise-native app —
  expected, not accidental.
- The Review-tab design is locked: see `prototypes/review-diff/NOTES.md` for the
  full spec (Variant D — C's sidebar × B's collapsible-file pane).
- **Support floor: a rolling window of the latest two macOS major releases** (as of
  2026-06, macOS 15 Sequoia + macOS 26; floor = macOS 15). This clears `MenuBarExtra`
  (13+) and `.symbolEffect` (14+), so no `NSStatusItem`/`NSPopover` fallback is
  needed. The trade-off: a Mac drops out of support each fall when a new major ships.
- **Distribution: build-from-source per device** (Xcode, local development signing) —
  no Apple Developer account, no notarization, no DMG. Updating Steve means pulling
  the repo and rebuilding on that device. We accept per-device build friction to avoid
  the $99/yr Developer Program; `SMAppService` login-item registration works under
  local development signing on the machine that built it. (Switching to Developer ID +
  notarized distribution later is possible if the friction outweighs the cost.)
