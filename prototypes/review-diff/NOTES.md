# Prototype verdict — Steve Review tab

> **Promoted to mockup:** [`mockups/review-tab/`](../../mockups/review-tab/) (v1) is the authoritative locked design. This prototype is retained as a record of the design exploration.

**Question:** What should the multi-skill diff review surface look/feel like?

**Decision: Variant D is locked. Keep this prototype for reference during the SwiftUI + WKWebView build.**

---

## How to run

```
cd prototypes/review-diff/app
npm install      # first time only
npm run dev      # opens on http://localhost:5199/
```

Opens on Variant D by default. Switch variants with `← →` arrow keys or the floating pill.

---

## Locked design: Variant D — C's sidebar × B's main pane

### Sidebar (from Variant C)
- **Sticky action header** always pinned at the top: 3-state select toggle + Update N + Skip N. Bulk actions never require scrolling to find.
- Grouped skill list below: Removed → Updates → Skipped → Up to date, alphabetical within each group.
- Checkboxes on all actionable skills; up-to-date skills shown without checkbox (non-selectable).
- State group labels coloured to match their state (red / blue / orange / gray).

### Main pane (from Variant B)
- **Collapsible file cards** — each file in the skill's diff gets its own card with ▼/▶ header. Cards open by default; clicking the header collapses.
- Card header shows: file name, status pill (Modified / Added / Deleted), line counts (+N / −N).
- **Materialising toolbar** appears when ≥ 1 skill is checked — sticky blue bar with the 3-state toggle, Update, Skip, and ✕ to dismiss. Provides an in-context action surface close to the diff content, complementing the always-visible sidebar header.
- Split (side-by-side) diff by default; Split / Unified toggle in the pane header.
- Up-to-date skill selected → "Up to date — nothing to sync" placeholder with GitHub link.

### 3-state select toggle (both surfaces)
Cycles: **Select all** (every actionable skill) → **Select new only** (Update available + Removed; excludes Skipped) → **Deselect all** → repeat.
- Icon: ☐ none → ☑ all → ⊟ new-only → ☐ none

### Diff direction
Base = Installed (S), head = Origin (O). Green = what Origin adds/changes; red = what's currently installed that Origin no longer has. Sides labelled **Installed** / **Origin**.

### Non-text files (decided — not in the prototype)
The unit is the whole skill directory, so a skill may carry non-text assets
(images, PDFs, fonts, compiled helpers). The prototype only models text diffs;
production handles binaries as follows:
- **Change detection** for *every* file is by **content hash**, so a changed binary
  still flips the skill to *Update available* and participates in Update/Skip.
- **Display**: text files get the normal diff; non-text files get a file card with
  the usual status pill (Modified / Added / Deleted) but a **"Binary — no preview"**
  body. Images *may* show before/after thumbnails.
- **Not in v1**: no visual image/PDF diffing.

---

## Why D over A, B, C

| Variant | Why not |
|---------|---------|
| A — Flat scroll | Persistent footer feels heavy; files always visible means long scrolling for multi-file skills |
| B — Collapsible | Good pane, but the toolbar being invisible until first check buries the bulk-action affordance |
| C — Three column | Good sidebar, but the extra file-tree column narrows the diff pane and adds visual weight for marginal benefit |
| **D — C sidebar + B pane** | Always-visible action header removes the discoverability problem of B; collapsible cards and the toolbar give a lightweight in-pane action surface; no wasted column |

---

## Variants A–C
Kept for context. Do not delete — useful reference for the SwiftUI build.

---

## Build notes (from the gap audit — apply in the SwiftUI build)
- **Render explicit "Installed" / "Origin" side labels** on the split diff. diff2html's
  split view does not label its two columns by default; the prototype hides its headers,
  so this must be added in the WKWebView build. (Direction: base = Installed (S), head = Origin (O).)
- **GitHub links use the resolved default branch**, not a literal. The prototype now
  uses `tree/master/...` to match reality, but the real app should read the default
  branch from the API (see ADR 0003) rather than hardcoding it.
- **Origin moving mid-review**: the Review window is an immutable snapshot at open;
  Update/Skip re-validate the live Origin SHA at commit time and block with a reload
  prompt if it moved (see ADR 0006). Not modelled in the prototype.
