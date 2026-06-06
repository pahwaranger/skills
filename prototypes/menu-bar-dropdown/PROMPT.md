# Prototype: Steve — menu-bar dropdown + icon states

Build a throwaway visual prototype of **Steve's menu-bar dropdown** and its three
**menu-bar icon states**, using the `/prototype` skill (UI branch). Goal: lock in
the look-and-feel before the real SwiftUI build.

## About Steve (shared context — you are starting cold)

Steve is a macOS **menu-bar agent** (native SwiftUI in production; `LSUIElement`,
no Dock tile) that syncs a personal fork of Claude Code skills onto a device. It
treats a public GitHub repo (`pahwaranger/skills`, the `skills/` directory) as
**Origin** and installs skills into the device's **skills directory**
(`~/.claude/skills/`). It keeps a private **Cache** = the last Origin state the
user has seen/acted on.

Per skill there are three versions: **O** = Origin, **C** = Cache, **S** = Skills
directory. Four states:

- **Up-to-date** — `S == O`. Not actionable.
- **Update available** — `O ≠ C` and `S ≠ O`. New, unseen; drives the attention icon.
- **Skipped** — `C == O` but `S ≠ O`. Seen and deferred.
- **Removed on origin** — a cached/installed skill Origin no longer has.

This is a **throwaway** web prototype for look-and-feel only. No networking, no
persistence — hardcode the fake data below.

## Locked decisions (constraints — do NOT change these)

The dropdown contents and order are fixed:

1. **Status indicator line** at the top.
2. **Check for updates** button.
3. **Skills list** — every managed skill, **grouped by state** in priority order
   (Removed on origin → Update available → Skipped → Up-to-date), **alphabetical
   within each group**. Rows are **minimal**: name + a leading state glyph/colour
   only (no timestamps or extra metadata).
4. **Settings** button (opens a separate window — not part of this prototype).
5. **Quit**.

Row click behaviour (show it as tooltip/affordance, no real navigation needed):
- Up-to-date row → "opens the skill's GitHub directory in the browser".
- Any non-up-to-date row → "opens the Review window".

**Status-line wording** (use these exact phrasings):
- Checking: `Checking origin…`
- Changes pending: `3 updates available · 1 removed · 1 skipped`
  (lead with badge items; append skipped count)
- All installed match origin, some deferred: `Up to date · 2 skipped`
- All clean: `Up to date · checked 3:00 PM`
- Failure: `Couldn't reach origin · checked 2h ago`

**Menu-bar icon — three states (must be depicted):**
- **Idle** — plain monochrome template icon (adapts to light/dark menu bar).
- **Checking** — the idle icon **pulsing** (subtle opacity/scale animation).
- **Attention** — the icon turns **red** (NOT a badge dot) whenever ≥1 skill is
  Update available or Removed on origin.

Render a small simulated macOS menu-bar strip above the dropdown showing Steve's
icon, with a control to flip between the three icon states so they can be felt.

## Fake data (use exactly this)

Managed skills and their states:

- **Removed on origin:** `zoom-out`
- **Update available:** `grill-with-docs`, `tdd`, `to-issues`
- **Skipped:** `handoff`
- **Up-to-date:** `diagnose`, `improve-codebase-architecture`, `prototype`,
  `setup-skills`, `to-prd`, `triage`

So the matching status line is: `3 updates available · 1 removed · 1 skipped`, and
the icon is in the **attention (red)** state. Also wire the icon-state control so a
reviewer can preview idle and checking.

## What the variants should explore (this is the open question)

The structure above is locked; vary the **visual & interaction treatment** so the
user can pick the feel. Default to **3 variants**, structurally distinct in their
visual language (not just colours):

- How the **status line** reads as the primary summary (quiet text line vs. a
  prominent banner vs. an icon+count chip row).
- **Row density and state encoding** (coloured dot + label vs. trailing pill badge
  vs. tinted full-row vs. SF-Symbols-style glyphs).
- Whether **group headers** are explicit labels, subtle dividers, or implicit via
  ordering + colour.
- Where the **Check for updates** affordance sits and how prominent it is.

Aim for a native-macOS popover feel (system font, ~300pt width, light/dark aware).

## How to build it

- Use the `/prototype` skill, **UI branch**. There is no existing app yet, so this
  is **sub-shape B** — a standalone throwaway route/page. Follow the skill's
  `?variant=` URL-param + floating bottom switcher-bar convention.
- One command to run. Plain HTML/CSS/JS or a tiny Vite app is fine — keep it light.
- No real fetch/mutations; everything is the hardcoded fake data above.

## When done

Capture which treatment wins and why in `NOTES.md` in this directory (the question
was: "what should the dropdown and icon states look/feel like?"). Leave a
placeholder verdict if the user hasn't weighed in yet.
