# Review tab — diff review surface for pending skill changes

**Version:** v1
**Provenance:** explored in [`prototypes/review-diff/`](../../prototypes/review-diff/)
**Production implementation:** `Steve/Steve/ReviewWindowView.swift`, `Steve/Steve/ReviewSidebarView.swift`, `Steve/Steve/DiffRendererView.swift`

## States

The states this surface can be in, and what triggers each. These map 1:1 to the
in-file state-switcher.

- **update-available** — default view; grill-with-docs (Update available) is selected, split diff rendered, no skills checked, materialising toolbar absent.
- **toolbar-visible** — three skills are checked (zoom-out, grill-with-docs, tdd); the materialising toolbar appears above the pane header.
- **unified-diff** — grill-with-docs selected; the diff is rendered in unified (line-by-line) view rather than the split default.
- **uptodate-selected** — an up-to-date skill (diagnose) is selected in the sidebar; the diff pane shows the "Up to date — nothing to sync" placeholder with a GitHub link.
- **all-resolved** — every actionable skill has been updated or skipped; the diff pane shows the "All caught up!" placeholder.

## Anatomy

The regions and components that make up the surface, named in `CONTEXT.md` vocabulary.

- **Window** — macOS-style window: 1200 × 740 px, rounded corners, drop shadow. Hosts the title bar and the two-tab row (Review active), then the win-content region below.
- **Sidebar** — left panel (200 px wide); uses `var(--sidebar-bg)`. Contains the action header pinned at the top and the scrollable skill list below.
- **Action header** — sticky strip at the top of the sidebar. Holds the 3-state select toggle (☐ / ☑ / ⊟), an Update N button (accent blue), and a Skip N button (secondary). Always visible without scrolling.
- **Skill list** — scrollable region below the action header. Skills grouped by state in priority order: Removed on origin → Update available → Skipped → Up-to-date. Group headers are uppercase, 10 px, coloured to match their state (`var(--state-removed)` / `var(--state-update)` / `var(--state-skipped)` / `var(--state-uptodate)`). Actionable skills have a checkbox; up-to-date skills show a blank space in place of the checkbox and are non-selectable (0.5 opacity).
- **Diff pane** — right panel, fills remaining width. Contains the materialising toolbar (when skills are checked), the pane header, and the diff scroll area.
- **Materialising toolbar** — a sticky blue bar (`var(--toolbar-bg)`) that appears at the top of the diff pane only when ≥ 1 skill is checked. Contains the 3-state select toggle, a checked-count label, Skip and Update buttons, and a ✕ dismiss button. Absent when nothing is checked.
- **Pane header** — permanent strip below the toolbar. Shows the selected skill name (bold, 13 px), a coloured state chip (Update / Removed / Skipped), a flex spacer, and the Split / Unified segmented control.
- **File card** — collapsible section in the diff scroll area, one per file in the selected skill's diff. Header shows: ▼/▶ chevron, filename in monospace, status pill (Modified / Added / Deleted), line-count badges (+N in green, −N in red). Body holds the baked diff table (split or unified). Cards are open by default; clicking the header collapses/expands.
- **3-state select toggle** — cycles: Select all actionable → Select new only (Update available + Removed; excludes Skipped) → Deselect all. Icon sequence: ☐ → ☑ → ⊟ → ☐. Present in both the action header and the materialising toolbar.

## Behavior & interactions

- Clicking a skill row in the sidebar → selects that skill and loads its diff cards in the diff pane.
- Clicking a file card header → toggles collapse/expand for that file card.
- Clicking the 3-state select toggle (action header or materialising toolbar) → cycles selection through Select all / Select new only / Deselect all.
- Checking/unchecking a skill checkbox → adds/removes from the checked set; materialising toolbar appears on first check, disappears when last check is cleared.
- Clicking Update N (action header or toolbar) → resolves all checked skills; they drop out of the sidebar; if the selected skill was resolved, the next actionable skill is auto-selected.
- Clicking Skip N (action header or toolbar) → same drop-out behaviour as Update (in this prototype both actions resolve the skill).
- Clicking ✕ on the toolbar → clears the checked set and hides the toolbar.
- Clicking Split / Unified in the pane header → toggles diff view for all file cards.
- Selecting an up-to-date skill → shows the "Up to date — nothing to sync" placeholder with a GitHub link.
- All actionable skills resolved → shows the "All caught up!" placeholder.
- ← / → arrow keys cycle through the mockup states (when no `<input>` or `<textarea>` is focused).
- `?state=<slug>` URL param restores the corresponding state on load.

## Tokens & measurements

Tokens are snapshotted in `tokens.css` (source: `prototypes/review-diff/app/src/styles.css`).

- Window size: 1200 × 740 px.
- Sidebar width: 200 px.
- Title bar height: 44 px.
- Tab bar padding: 6 px top / 10 px bottom.
- Action header padding: 8 px vertical / 10 px horizontal.
- Skill row padding: 5 px vertical / 8–10 px horizontal; font-size 12 px.
- Group header: 10 px, weight 700, uppercase, letter-spacing 0.04 em.
- File card header: 12.5 px; 8 px vertical / 14 px horizontal padding.
- Pane header: 13 px; 8 px vertical / 14 px horizontal padding.
- Toolbar: 12.5 px, weight 500; 7 px vertical / 14 px horizontal padding.
- State chip: 10 px, weight 700, letter-spacing 0.03 em, 1 px / 7 px padding, pill radius.
- Status pill: 10 px, weight 600; Modified → `rgba(10,132,255,0.12)` bg / `var(--state-update)` text; Added → `rgba(48,164,108,0.12)` bg / `#1a8a4a` text; Deleted → `rgba(229,72,77,0.12)` bg / `var(--state-removed)` text.
- Line count badges: 11 px, weight 600; added → `#1a8a4a`; removed → `var(--state-removed)`.
- Diff table: "SF Mono", ui-monospace, Menlo; 12 px; line-height 1.7.
- Line number gutter: 36 px wide, right-aligned, 11 px, `var(--text-secondary)`, `rgba(127,127,127,0.06)` bg.
- Added row bg: `rgba(48,209,88,0.10)`; removed row bg: `rgba(229,72,77,0.10)`.
- Dark mode overrides: see `tokens.css`.

## Constraints & open questions

- **Constraint:** diff content is a fixed snapshot from `prototypes/review-diff/app/src/data.ts`; the mockup uses baked static HTML tables (no diff2html library) because the mockup must be no-build / self-contained.
- **Constraint:** diff direction is base = Installed (S), head = Origin (O). Green = what Origin adds; red = what's currently installed that Origin no longer has. Split diff columns are labelled "Installed" / "Origin".
- **Constraint:** up-to-date skills are always shown in the sidebar (non-selectable, 0.5 opacity, no checkbox) — they are context, not work items.
- **Constraint:** no real mutations — Update/Skip in the mockup "resolve" skills by removing them from the visible set (in-memory only, no persistence).
- **Open question:** the NOTES.md build note says the SwiftUI build must add explicit "Installed" / "Origin" column labels on the split diff (diff2html omits them by default). The mockup includes these labels in the static diff tables; confirm placement is correct before the WKWebView build.
- **Open question:** the 3-state toggle icon sequence (☐ / ☑ / ⊟) uses Unicode characters; the native SwiftUI build will need SF Symbols equivalents.
