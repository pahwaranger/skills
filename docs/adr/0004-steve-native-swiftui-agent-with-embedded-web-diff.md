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
