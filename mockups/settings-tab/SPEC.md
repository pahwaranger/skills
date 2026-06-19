# Settings tab — app preferences surface for Steve

**Version:** v1
**Provenance:** explored in [`prototypes/settings/`](../../prototypes/settings/)
**Production implementation:** `Steve/Steve/SettingsView.swift`

## States

The states this surface can be in, and what triggers each. These map 1:1 to the
in-file state-switcher.

- **checks-on** — default; Automatic checks toggle is on; the Minutes between checks stepper is enabled and shows 60 min.
- **checks-off** — Automatic checks toggle is off; the Minutes between checks stepper stays visible but is greyed (0.38 opacity) and disabled; the Syncing section caption switches to explain that Steve only checks on demand.

## Anatomy

The regions and components that make up the surface, named in `CONTEXT.md` vocabulary.

- **Window** — macOS-style window: 560 px wide; height determined by content (~420 px with padding). Rounded corners, drop shadow. Hosts the title bar and the two-tab row (Settings active), then the content region.
- **Title bar** — 44 px high; `var(--titlebar-bg)`; traffic-light buttons left, "Steve" centred.
- **Tab row** — Review and Settings tabs; Settings is active (`var(--tab-active-bg)` highlight). Uses icon glyphs: ⤓ (Review), ⚙ (Settings).
- **Content area** — `var(--content-bg)`; 22 px padding on all sides. Contains two grouped sections.
- **Syncing section** — grouped card (`var(--card-bg)`, 10 px radius, 0.5 px border). Caption header ("Syncing") above the card in uppercase 11 px `var(--text-secondary)`. Contains two rows: the Automatic checks row and the nested Minutes between checks row.
- **Automatic checks row** — label ("Automatic checks", 13 px weight 500) left; toggle switch right.
- **Nested interval row** — indented 30 px from the left edge; sits directly below the Automatic checks row with a `rgba(127,127,127,0.05)` tinted background. Contains label ("Minutes between checks", 13 px) with a sub-caption ("How often Steve looks at Origin for changes.", 11 px `var(--text-secondary)`) and a stepper control on the right. Stays visible (does not collapse) when Automatic checks is off; instead the label and stepper grey to 0.38 opacity and become non-interactive.
- **Section caption** — 11 px `var(--text-secondary)`; 7 px top margin below the card. Syncing caption text changes based on Automatic checks state (see Behavior).
- **General section** — grouped card same style as Syncing. Caption header "General" above. Contains two rows: Launch at login (toggle) and Default diff view (segmented control).
- **Toggle switch** — 38 × 23 px pill; thumb slides 15 px on check; `var(--accent)` track when on, `var(--track-off)` when off.
- **Stepper** — number input (56 px wide) + up/down bump buttons + "min" unit label. Range 1–1440.
- **Segmented control** — Split / Unified; 8 px radius container, selected segment gets white bg + shadow.

## Behavior & interactions

- Toggling Automatic checks on → enables the nested interval row (removes disabled state); caption reads "Steve checks Origin on this interval and flags changes in the menu bar."
- Toggling Automatic checks off → disables (greys) the nested interval row (does not hide it); caption reads "Off — Steve only checks when you choose 'Check for updates' from the menu."
- The nested interval row remains at full height at all times — it never collapses or disappears (this is the key difference from prototype Variant B).
- Clicking stepper bump buttons → increments/decrements minutes by 1, clamped to 1–1440.
- Typing in the minutes input → value clamped to 1–1440 on blur.
- Toggling Launch at login → in-memory only (no persistence in mockup).
- Clicking Split / Unified segmented control → updates selection in-memory.
- ← / → arrow keys cycle through the mockup states (when no `<input>` or `<textarea>` is focused).
- `?state=<slug>` URL param restores the corresponding state on load.

## Tokens & measurements

Tokens are snapshotted in `tokens.css` (source: `prototypes/settings/index.html` inline `<style>`).

- Window width: 560 px.
- Title bar height: 44 px.
- Tab row padding: 6 px top / 12 px bottom.
- Content area padding: 22 px.
- Section card: `var(--card-bg)`; 10 px border-radius; 0.5 px `var(--separator)` border.
- Card row padding: 12 px vertical / 14 px horizontal.
- Nested row left indent: 30 px; background `rgba(127,127,127,0.05)`.
- Disabled state opacity: 0.38.
- Section caption: 11 px, `var(--text-secondary)`, 7 px top margin.
- Section header label: 11 px, weight 600, uppercase, letter-spacing 0.04 em, `var(--text-secondary)`, 7 px bottom margin, 4 px left margin.
- Toggle switch: 38 × 23 px; thumb 19 × 19 px, 2 px from edges; transition 0.18 s.
- Stepper input: 56 px wide, 13 px font, right-aligned, 6 px radius, `var(--control-border)` border.
- Segmented control: `var(--segment-bg)` bg, 8 px radius, 2 px inner padding; selected segment `var(--segment-sel)` bg + `0 1px 2px rgba(0,0,0,0.18)` shadow; button 12 px font, 4 px vertical / 14 px horizontal padding.
- Dark mode overrides: see `tokens.css`.

## Constraints & open questions

- **Constraint:** exactly four controls — Launch at login, Automatic checks, Minutes between checks, Default diff view. No other settings are exposed.
- **Constraint:** the interval row is always visible (never collapses) when Automatic checks is off. It greys to 0.38 opacity and `pointer-events: none`. This is the locked design choice over Variant B (collapse/hide).
- **Constraint:** defaults are Launch at login on, Automatic checks on, Minutes 60, Default diff view split.
- **Constraint:** no persistence — all controls update in-memory state only.
- **Open question:** the native SwiftUI toggle style may differ from the HTML pill switch; confirm that the greyed-but-visible treatment translates correctly to `.disabled` modifier on a `Toggle` in SwiftUI (opacity should be similar but check against macOS HIG).
