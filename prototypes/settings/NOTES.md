# Settings tab — prototype notes

**Question being answered:** What should Steve's Settings tab look like, and how
should the disabled-interval dependency (*Minutes between checks*, when *Automatic
checks* is off) read?

## Verdict — LOCKED ✅ (variant C)

**Grouped sections, with the interval nested under its toggle and disabled (not
hidden) when Automatic checks is off.**

- **Layout:** two captioned cards — **Syncing** (Automatic checks + Minutes between
  checks) and **General** (Launch at login + Default diff view). Reads as a native
  macOS settings pane and makes the two concerns legible at a glance.
- **Dependency treatment:** *Minutes between checks* is an indented row **nested
  directly under** the Automatic-checks toggle, so the parent/child relationship is
  obvious. When Automatic checks is **off**, the interval row **stays visible but
  greys out / disables** (it does not collapse or disappear), and the section
  caption switches to explain that Steve only checks on demand.

Why C over the alternatives:
- vs **A (flat form, greyed inline):** C's grouping ties the interval to its
  controlling toggle visually; the flat list left that relationship implicit.
- vs **B (nested + collapse/hide):** keeping the interval visible-but-disabled
  preserves discoverability — the user can see the setting exists and what it's set
  to even while it's inactive — without the layout jumping as a row appears/vanishes.

## The variants explored (all kept as context)

All three remain in `index.html`, reachable from the floating switcher bar (or
`?variant=A|B|C`; the page opens on the locked choice, C). They share identical
window chrome and the same four controls — they differ only in layout and how the
disabled-interval dependency reads. Kept deliberately as design context for the
SwiftUI build; **do not delete them.**

| | A — Flat form | B — Grouped + collapse | **C — Grouped + disable (LOCKED)** |
|---|---|---|---|
| Layout | One vertical list of label↔control rows | Two captioned cards (Syncing / General) | Two captioned cards (Syncing / General) |
| Interval when checks off | Stays in place, **greyed inline**; one-line hint | **Nested** under toggle, **collapses away** | **Nested** under toggle, **stays visible, greys/disables** |
| Reads as | "all here, this one's inactive" | "belongs to that toggle, gone when N/A" | "belongs to that toggle, inactive right now" |

## What ships (for the SwiftUI build)

This locked layout is the spec for the native Settings tab:

- Window chrome: traffic-light title bar titled **Steve**, two-tab row with
  **Review** and **Settings**, Settings active. (This prototype establishes the
  shared chrome; the Review prototype should match it.)
- Four controls only, with defaults: Launch at login **on**, Automatic checks
  **on**, Minutes between checks **60**, Default diff view **split**.
- Disabled-when-parent-off behaviour for the interval as described above.

## How to run (prototype)

```
python3 prototypes/settings/serve.py
# open http://localhost:8755/
```

Self-contained `index.html`, no build, no persistence — controls flip in-memory
state only. Opens on the locked variant C; A and B stay reachable via the switcher.

## Cleanup

Throwaway. Once the SwiftUI Settings tab implements the locked **C** layout, delete
this directory (`index.html`, `serve.py`) and the `settings-prototype` entry in
`.claude/launch.json`. (The variant comparison lives on here and in this file until
then — that's the point of keeping A and B around.)
