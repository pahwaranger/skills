# Steve — Menu-Bar Dropdown: Prototype Notes

**Question answered:** What should the dropdown and icon states look/feel like?

**Prototype:** `index.html` — three variants, `?variant=A/B/C`, floating switcher bar.  
**Run:** `python3 -m http.server 3400` from this directory (or open via Claude Code preview).

---

## The three variants

| | A — Quiet | B — Structured | C — Chips |
|---|---|---|---|
| **Status line** | Muted single text line | Tinted banner with title + sub-text | Row of colored pill-chips (counts) |
| **Check for updates** | Inline `↺ Check` text-link (right-aligned) | Dedicated full-width button below banner | Icon-only `↺` button, trailing in chip row |
| **Group headers** | None — thin rules between groups | Explicit uppercase labels (REMOVED ON ORIGIN, etc.) | None — trailing badge per row tells the story |
| **State encoding** | 7px colored leading dot | 3px left-bar accent on row | Trailing pill badge (removed / update / skipped) |
| **Character** | Power-user dense; info without ceremony | Clear zones; unmissable status; scannable categories | At-a-glance badges; status is on the item, not the header |

## Verdict

> **B — Structured** ✓

Three explicit zones work well for a sync agent: the banner makes the attention state unmissable (important when Steve is the mechanism for knowing something changed), the full-width Check button is easy to reach, and the uppercase section labels mean you never have to infer grouping from dot color alone. The left-bar accents give each row a clear state signal without cluttering the name.

A and C are eliminated. Delete their render functions and the switcher when promoting to SwiftUI.

## Icon states

The prototype exposes Idle / Checking / Attention as a mutually-exclusive toggle,
but in production they are **two independent axes**, because a check can run while
updates are already pending:

- **Base colour** — monochrome `↺` (Idle, adapts to light/dark menu bar) **or**
  solid `#FF3B30` macOS system red (Attention: ≥1 skill Update available or Removed
  on origin). No badge dot.
- **Pulsing** — an opacity pulse (~1.5s cycle) layered on whenever a check is in
  flight, in the *current* base colour.

So **Checking is a modifier, not a third state**. Precedence (decided): checking
pulses the current colour — a check while pending = **pulsing red**; a check while
clean = **pulsing monochrome**. The icon settles to its base colour when the check
finishes. No issues with either base colour across light and dark mode.

## Build notes (from verification pass)

**Caret arrow** — the prototype renders a CSS triangle pointing from the dropdown up to the icon. `MenuBarExtra .window` style does not produce this; it's a borderless floating panel. **Decision: drop the caret.** Use `MenuBarExtra(.window)` — no `NSPopover` needed. This is consistent with many production menu bar apps.

**Settings window** — `SettingsLink` doesn't work reliably from `MenuBarExtra` context. Opening a separate Settings window requires a hidden background `Window` scene + activation policy juggling. See [Steipete's write-up (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items). Doesn't affect the dropdown design.

**Animated icon** — `.symbolEffect(.pulse)` on macOS 14+; manual opacity `withAnimation(.easeInOut.repeatForever())` on macOS 13. Worth a quick smoke-test in the actual menu bar renderer before shipping.

**Minimum target** — support policy is a **rolling window of the latest two macOS major releases** (as of 2026-06 that's macOS 15 Sequoia + macOS 26; floor = macOS 15). That clears `MenuBarExtra` (13+) and `.symbolEffect` (14+) with margin, so the `NSStatusItem` + `NSPopover` fallback is **not needed**.
