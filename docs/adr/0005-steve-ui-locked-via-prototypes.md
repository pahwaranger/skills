# Steve's UI is locked via retained throwaway prototypes

Before the SwiftUI build, each of Steve's three UI surfaces was prototyped as
several switchable variants (the `/prototype` UI branch) and one was chosen per
surface. Those choices are the **UI spec** for the native build. Unusually for
throwaway prototypes, **we are keeping them in the repo** (`prototypes/`) rather
than deleting them — they are living reference for the SwiftUI work and a record of
the rejected alternatives, which is cheaper to consult than to reconstruct.

## Decisions

| Surface | Locked variant | Prototype | Verdict |
|---------|----------------|-----------|---------|
| Menu-bar dropdown + icon states | **B — Structured** (tinted status banner, full-width Check button, explicit uppercase group labels, left-bar row accents) | [`prototypes/menu-bar-dropdown/`](../../prototypes/menu-bar-dropdown/) | [NOTES](../../prototypes/menu-bar-dropdown/NOTES.md) |
| Review tab (multi-skill diff) | **D — C's sidebar × B's pane** (sticky action header + grouped sidebar; collapsible per-file cards + materialising toolbar; split default) | [`prototypes/review-diff/`](../../prototypes/review-diff/) | [NOTES](../../prototypes/review-diff/NOTES.md) |
| Settings tab | **C — Grouped + disable** (two captioned cards; interval nested under its toggle, greyed-but-visible when automatic checks are off) | [`prototypes/settings/`](../../prototypes/settings/) | [NOTES](../../prototypes/settings/NOTES.md) |

The detailed rationale and the rejected variants for each surface live in that
surface's `NOTES.md`. UI vocabulary that came out of these choices (Review tab,
Sidebar, Action header, Diff pane, File card, Materialising toolbar, 3-state select
toggle) is defined in [CONTEXT.md](../../CONTEXT.md).

## Consequences

- The prototypes are **retained, not throwaway** — this ADR overrides the
  "delete when done" cleanup notes inside the prototype directories. They stay until
  the native UI both ships and is judged not to need them.
- The dropdown prototype also surfaced macOS build constraints worth heeding (drop
  the popover caret and use `MenuBarExtra(.window)`; `MenuBarExtra` requires macOS 13;
  Settings-window activation needs care) — see its NOTES.
