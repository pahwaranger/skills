# Steve — UI prototypes

Throwaway visual prototypes for **Steve**, the macOS menu-bar app that syncs this
skills fork onto a device (see [ADR 0004](../docs/adr/0004-steve-native-swiftui-agent-with-embedded-web-diff.md)).
Their purpose is to **lock in the look-and-feel** of the three UI surfaces before
the SwiftUI build — not to re-open design questions already settled in the grilling
session.

Each subdirectory has a self-contained `PROMPT.md` that a separate agent can use to
build that surface with the `/prototype` skill (UI branch). The structural
decisions are fixed constraints; the variants explore the genuinely-open visual and
interaction treatments within them.

| Prototype | Surface | Status | Verdict |
|-----------|---------|--------|---------|
| [`menu-bar-dropdown/`](./menu-bar-dropdown/PROMPT.md) | Dropdown panel + three menu-bar icon states | ⬜ Not built | — |
| [`review-diff/`](./review-diff/NOTES.md) | Review tab — sidebar + diff pane + selection + bulk actions | ✅ Locked | Variant D: sticky action header sidebar × collapsible file cards pane — see NOTES.md |
| [`settings/`](./settings/NOTES.md) | Settings tab | ✅ Locked | Variant C: grouped sections, interval nested + disabled (not hidden) — see NOTES.md |

These are **throwaway** (no networking, no persistence — fake data only). When a
treatment wins, capture the verdict in a `NOTES.md` next to that prototype. The
prototype stays here permanently as a record of how the decision was reached — do
not delete it. Promote the winner to a mockup via the [`mockup`](../skills/mockup/SKILL.md)
skill; the mockup becomes the authoritative design reference for production to build from.
