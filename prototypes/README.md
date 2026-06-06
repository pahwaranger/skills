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

| Prototype | Surface | What it locks in |
|-----------|---------|------------------|
| [`menu-bar-dropdown/`](./menu-bar-dropdown/PROMPT.md) | The dropdown panel + the three menu-bar icon states | Density, status-line treatment, row/state visual language |
| [`review-diff/`](./review-diff/PROMPT.md) | The Review tab (sidebar of skills + PR-style diff + selection + bulk actions) | Diff density, file organization, how selection & bulk actions are surfaced |
| [`settings/`](./settings/PROMPT.md) | The Settings tab | Form layout and how dependent controls are grouped |

These are **throwaway** (no networking, no persistence — fake data only). When a
treatment wins, capture the verdict in a `NOTES.md` next to that prototype, then
fold the decision into the real app and delete the rest.
