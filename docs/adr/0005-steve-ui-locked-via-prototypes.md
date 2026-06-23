# Steve's UI is locked via living mockups

Before the SwiftUI build, each of Steve's three UI surfaces was prototyped as
several switchable variants (the `/prototype` UI branch) and one was chosen per
surface. Those choices are now the **authoritative UI spec** for the native build,
published as **living mockups** in `mockups/`. The prototype explorations are
retained in the repo (`prototypes/`) as records of how the decisions were reached
and a reference for the rejected alternatives, which is cheaper to consult than to
reconstruct.

## Decisions

| Surface | Locked variant | Mockup | Spec |
|---------|----------------|---------|------|
| Menu-bar dropdown + icon states | **B — Structured** (tinted status banner, full-width Check button, explicit uppercase group labels, left-bar row accents) | [`mockups/menu-bar-dropdown/`](../../mockups/menu-bar-dropdown/) | [SPEC.md](../../mockups/menu-bar-dropdown/SPEC.md) |
| Review tab (multi-skill diff) | **D — C's sidebar × B's pane** (sticky action header + grouped sidebar; collapsible per-file cards + materialising toolbar; split default) | [`mockups/review-tab/`](../../mockups/review-tab/) | [SPEC.md](../../mockups/review-tab/SPEC.md) |
| Settings tab | **C — Grouped + disable** (two captioned cards; interval nested under its toggle, greyed-but-visible when automatic checks are off) | [`mockups/settings-tab/`](../../mockups/settings-tab/) | [SPEC.md](../../mockups/settings-tab/SPEC.md) |

The detailed rationale and the rejected variants for each surface live in that
surface's prototype `NOTES.md` — see
[menu-bar-dropdown](../../prototypes/menu-bar-dropdown/NOTES.md),
[review-diff](../../prototypes/review-diff/NOTES.md), and
[settings](../../prototypes/settings/NOTES.md). UI vocabulary that came out of these choices
(Review tab, Sidebar, Action header, Diff pane, File card, Materialising toolbar,
3-state select toggle) is defined in [CONTEXT.md](../../CONTEXT.md).

## Consequences

- The **living mockups** in `mockups/` are the authoritative design reference —
  they are kept current as the UI evolves, and developers replicate them in the
  production app. Each mockup is versioned; when specifying UI work, cite the
  specific mockup and version (e.g. `mockups/review-tab` v1).
- The **prototype explorations** in `prototypes/` are retained as reference records
  of how the decisions were reached. They carry no production dependency (production
  never imports them) and are not updated as the design evolves. Retention is the
  default behavior of the `prototype` skill; these are not exceptional.
- The menu-bar dropdown exploration also surfaced macOS build constraints worth
  heeding (drop the popover caret and use `MenuBarExtra(.window)`; `MenuBarExtra`
  requires macOS 13; Settings-window activation needs care) — see the prototype's
  documentation and the production implementation notes.
