# Menu-bar dropdown — sync-status panel and icon states for Steve

**Version:** v1
**Provenance:** explored in [`prototypes/menu-bar-dropdown/`](../../prototypes/menu-bar-dropdown/)
**Production implementation:** `Steve/Steve/DropdownView.swift`, `Steve/Steve/SteveApp.swift`

## States

The states this surface can be in, and what triggers each. These map 1:1 to the
in-file state-switcher. **Default (index 0) is `attention`** — the populated state
with all four buckets visible.

- **attention** *(default)* — full attention state: 1 removed on origin, 3 updates available, 1 skipped, 6 up-to-date; banner reads "Attention required · 3 updates available · 1 removed · 1 skipped"; all four section buckets rendered; icon is solid red.
- **updates** — updates only (no removed, no skipped): 3 updates available, 6 up-to-date; banner reads "Updates available · 3 updates available"; two section buckets (Update available + Up to date); icon is solid red.
- **removed** — removed only (no updates, no skipped): 1 removed on origin, 6 up-to-date; banner reads "Attention required · 1 removed on origin"; two section buckets (Removed on origin + Up to date); icon is solid red.
- **up-to-date** — clean state; no pending updates or removals; banner shows "All skills up to date"; skill list shows current skills only (no section header); icon is monochrome idle.
- **checking** — a check is in flight (triggered manually or by scheduler); banner reads "Checking…"; Check for updates button is disabled with an inline spinner; icon pulses in monochrome (no prior attention in this state — would pulse red if attention were already active).

## Anatomy

The regions and components that make up the surface, named in `CONTEXT.md` vocabulary.

- **Menu-bar icon** — Steve's status-bar item rendered as `↺` in the macOS menu bar. Defined by two independent axes: **base colour** (monochrome when idle; solid `#FF3B30` when attention — ≥1 Update available or Removed on origin) × **pulsing** (opacity animation ~1.5 s cycle, overlaid in the current base colour while a check is in flight). Checking is a modifier, not a third state: a check while pending shows as pulsing red. No badge dot.
- **Dropdown panel** — 300 px wide borderless floating panel anchored below the menu-bar icon. `MenuBarExtra(.window)` style — no NSPopover caret. Four vertical zones (top → bottom): Status banner → Check for updates button → Skill list → Footer.
- **Status banner** — Zone 1. Horizontal strip with a circular icon badge on the left and a two-line text block (title + sub-text) on the right. Tinted `rgba(255,59,48,0.06)` background in attention states; no tint in clean or checking states. Badge colour matches state: red circle with "!" for attention, grey circle with "↺" for checking, green circle with "✓" for up-to-date.
- **Check for updates button** — Zone 2. Full-width rounded bubble button: explicit light-gray fill (`#E5E5EA` light / `rgba(255,255,255,0.14)` dark), 1 px visible border, 8 px border-radius, `var(--tlink)` label, full width minus 14 px side margins (`calc(100% - 28px)`). Renders as a standard macOS bordered button — clearly distinct from the background. Disabled with an inline CSS spinner when a check is in flight.
- **Skill list** — Zone 3. Skills grouped by state in priority order: Removed on origin → Update available → (Skipped) → Up to date. Each non-current group is preceded by an uppercase section label (10.5 px, weight 600, `var(--t3)`, 0.07 em letter-spacing). Each row is 26 px tall with a 3 px left-bar accent inset 9 px from the left edge; accent colour: `var(--cr)` removed, `var(--cu)` update, `var(--cs)` skipped, transparent for current. A thin separator (`var(--sep)`) divides actionable groups from the up-to-date group.
- **Footer** — Zone 4. "Settings…" and "Quit Steve" rows, 26 px each, no left-bar accent. Separated from the skill list by a `var(--sep)` top border.
- **Icon reference strip** — Mockup scaffolding only (not part of the production design). A labelled row below the scene showing all four icon renderings: idle, pulsing-clean, attention-red, pulsing-red.
- **State-switcher** — Mockup scaffolding only. Fixed pill at the bottom of the viewport; ‹ / › buttons and arrow keys cycle through the five panel states.

## Behavior & interactions

- Icon base colour changes to `#FF3B30` whenever `lastDerivedState` contains ≥1 skill in `removedOnOrigin` or `updateAvailable` state; reverts to monochrome when all skills are current.
- Icon pulsing activates (CSS opacity animation) whenever `isChecking` is true, regardless of base colour; stops when the check completes.
- Tapping the menu-bar icon opens the dropdown panel; tapping outside dismisses it (`MenuBarExtra(.window)` handles this natively).
- Clicking "↺ Check for updates" → triggers `appModel.triggerCheck()`; button immediately disables and shows spinner; re-enables when check completes.
- Clicking a skill row in the Removed on origin, Update available, or Skipped section → sets `appModel.reviewFocusSkill` to that skill name, sets `appModel.selectedTab = .review`, and calls `openWindow(id: "main")` to open/raise the Review window.
- Clicking a skill row in the Up to date section → opens the skill's GitHub directory in the browser (using the resolved default branch).
- Clicking "Settings…" → sets `appModel.selectedTab = .settings`, calls `openWindow(id: "main")`. (`SettingsLink` is unreliable from `MenuBarExtra` context — see NOTES.md.)
- Clicking "Quit Steve" → calls `NSApplication.shared.terminate(nil)`.
- ← / → arrow keys cycle the mockup states (when no `<input>` or `<textarea>` is focused).
- `?state=<slug>` URL param restores the corresponding state on load.

## Tokens & measurements

Tokens are snapshotted in `tokens.css` (source: `prototypes/menu-bar-dropdown/index.html` inline `<style>`).

- Dropdown panel width: 300 px.
- Border radius: 12 px.
- Banner padding: 9 px vertical / 14 px horizontal.
- Banner tint (attention): `rgba(255,59,48,0.06)`.
- Banner badge: 22 × 22 px circle; attention `rgba(255,59,48,0.12)` bg / `#FF3B30` text; checking `rgba(142,142,147,0.12)` bg / `var(--t3)` text; clean `rgba(52,199,89,0.12)` bg / `#34C759` text.
- Banner title: 13 px, weight 500, `var(--t1)`.
- Banner sub-text: 11 px, `var(--t2)`, 1 px top margin.
- Check button: `var(--btn-bg)` fill; `var(--btn-border)` border; `var(--tlink)` label; 7 px border-radius; 5 px vertical padding; 14 px horizontal margin (full-width minus margins).
- Section label: 10.5 px, weight 600, `var(--t3)`, `text-transform: uppercase`, `letter-spacing: 0.07em`; padding 6 px top / 2 px bottom / 14 px horizontal.
- Skill row height: 26 px; left-bar accent 3 × (row height − 12) px, 2 px radius, 9 px from left, 6 px inset top/bottom.
- Hover background: `var(--hover)`.
- Footer: `var(--sep)` top border; 3 px vertical padding; rows 26 px, 14 px horizontal padding, no accent.
- Separator: 1 px `var(--sep)`, 3 px vertical margin.
- Menu-bar icon: `↺` glyph, 14 px; monochrome at 0.82 opacity (idle); `#FF3B30` at 1.0 opacity (attention); opacity pulse `0.82 → 0.18 → 0.82` over 1.5 s ease-in-out when checking.
- Dark mode overrides: see `tokens.css`.

## Constraints & open questions

- **Constraint:** Variant B only — Variant A (Quiet) and Variant C (Chips) render paths are dropped. The locked design is Variant B.
- **Constraint:** no NSPopover caret. The production app uses `MenuBarExtra(.window)` (borderless floating panel), not `NSPopover`. The caret present in the prototype's CSS is not reproduced here.
- **Constraint:** icon is two independent axes (base colour × pulsing), not a three-way enum. Pulsing is a modifier that layers onto whichever base colour is currently active.
- **Constraint:** `.symbolEffect(.pulse)` is available on macOS 14+; the support floor is macOS 15 (rolling two-release window as of 2026-06), so this is cleared with margin.
- **Constraint:** "Settings…" must open the main window rather than using `SettingsLink` (unreliable from `MenuBarExtra` context — see `prototypes/menu-bar-dropdown/NOTES.md` and the Steipete 2025 write-up cited there).
- **Open question:** how many skills can appear in the list before the panel height becomes unwieldy? The production `MenuBarExtra(.window)` will need a max-height + scroll container if the installed skill count grows large.
- **Open question:** the "checking" state in the mockup assumes a clean baseline (icon pulses monochrome). A richer "checking while attention" scenario (pulsing red) is depicted in the icon reference strip but is not a separate panel state — confirm this is sufficient or add a fifth state.
