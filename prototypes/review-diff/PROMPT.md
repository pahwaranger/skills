# Prototype: Steve — Review tab (multi-skill diff review)

Build a throwaway visual prototype of **Steve's Review tab** — the multi-skill,
GitHub-PR-style diff review surface — using the `/prototype` skill (UI branch).
This is the most complex and highest-risk UI in the app; goal is to lock in its
look-and-feel before the SwiftUI + WKWebView build.

## About Steve (shared context — you are starting cold)

Steve is a macOS **menu-bar agent** that syncs a personal fork of Claude Code
skills onto a device. It treats a public GitHub repo (`pahwaranger/skills`, the
`skills/` directory) as **Origin** and installs skills into the device's **skills
directory** (`~/.claude/skills/`). It keeps a private **Cache** = the last Origin
state the user has seen.

Per skill, three versions: **O** = Origin, **C** = Cache, **S** = Skills
directory. Four states:

- **Up-to-date** — `S == O`. Not actionable.
- **Update available** — `O ≠ C` and `S ≠ O`. New, unseen.
- **Skipped** — `C == O` but `S ≠ O`. Seen and deferred.
- **Removed on origin** — a cached/installed skill Origin no longer has.

The **unit is the whole skill directory** (every file), not just `SKILL.md`. In
production this diff renders inside a `WKWebView` using a web diff library, so a
web prototype is faithful to the real thing — **prefer using
[`diff2html`](https://github.com/rtfpessoa/diff2html)** (or similar) so the
rendering matches what ships.

This is a **throwaway** prototype: no networking, no persistence, fake diffs only.

## Locked decisions (constraints — do NOT change these)

This surface is the **Review tab** of a two-tab window (the other tab is Settings,
prototyped separately). Render the window chrome — a title bar and the two tabs —
with **Review** active.

- **Layout: left sidebar + main diff pane.** The sidebar lists skills; the main
  pane shows the selected skill's diff. (Sidebar layout is decided — do not replace
  it with tabs or a single scrolling stack.)
- **Sidebar membership = ALL managed skills**, grouped by state in priority order
  (Removed on origin → Update available → Skipped → Up-to-date), alphabetical
  within each group — i.e. it mirrors the menu-bar list.
- **Up-to-date skills appear but are non-selectable** (no checkbox, disabled).
  Selecting one shows a placeholder ("Up to date — nothing to sync") with a link to
  open the directory on GitHub. They are context, not work items.
- **Diff direction:** base = **Installed (S)**, head = **Origin (O)**. Green
  additions = what Origin would add/change; red removals = what's currently
  installed that Origin no longer has. Label the two sides **"Installed"** and
  **"Origin"**.
- **Diff view: split (side-by-side) by default**, with a **toggle to unified**.
- **New skill** (not installed) → entire directory shown as all-additions.
  **Removed on origin** → entire directory shown as all-deletions.
- **Selection:** each actionable (non-up-to-date) skill has a **checkbox**. A
  **3-state "select" toggle** rotates through: **Select all** (every actionable
  skill) → **Select all new** (Update available + Removed on origin only; excludes
  Skipped) → **Deselect all**.
- **Bulk actions footer:** **Update selected** and **Skip selected**.
  - *Update* = "copy Origin into both Cache and Skills directory" (for Removed,
    deletes from both).
  - *Skip* = "copy Origin into Cache only" (install untouched).
  - Each skill row may also offer its own Update / Skip.
- Resolved skills drop out as they're actioned; window closes when nothing
  reviewable remains (simulate visually — no real mutations).
- Opening the window from a menu row focuses **that** skill; others sit collapsed
  in the sidebar.

## Fake data (use exactly this)

Sidebar skills and states (same set as the rest of the app):

- **Removed on origin:** `zoom-out`
- **Update available:** `grill-with-docs`, `tdd`, `to-issues`
- **Skipped:** `handoff`
- **Up-to-date:** `diagnose`, `improve-codebase-architecture`, `prototype`,
  `setup-skills`, `to-prd`, `triage`

Open focused on **`grill-with-docs`**. Give it a realistic **multi-file** diff so
the per-directory nature is visible:

- `grill-with-docs/SKILL.md` — **modified** (a few changed lines in the description
  and a tweaked step).
- `grill-with-docs/CONTEXT-FORMAT.md` — **modified** (a couple of added rule lines).
- `grill-with-docs/EXAMPLES.md` — **added** (new supporting file, all green).

For `tdd` and `to-issues`, a single modified `SKILL.md` each is enough. For
`zoom-out` (Removed on origin), show the whole directory as deletions. Invent
plausible markdown content for all diffs — it just needs to look like real skill
files.

## What the variants should explore (this is the open question)

Structure is locked (sidebar + diff pane + bulk footer). Vary the **treatment** so
the user can pick the feel. Default to **3 variants**, meaningfully distinct:

- **Within a skill, how multiple files are organized**: a flat scrolling sequence
  of file diffs vs. a collapsible per-file list (GitHub "Files changed" style) vs.
  a secondary file-tree column.
- **Diff density & chrome**: line-number gutter style, hunk headers, file-status
  pills (Modified/Added/Deleted), how the split↔unified toggle is presented.
- **How selection + bulk actions are surfaced**: persistent footer bar vs. a
  selection toolbar that appears on first check vs. sidebar-integrated checkboxes
  with a sticky action header. Make the **3-state select toggle** legible in each.
- **Sidebar state encoding & grouping** (consistent with the menu-bar prototype's
  visual language where possible).

Native-macOS window feel; light/dark aware.

## How to build it

- Use the `/prototype` skill, **UI branch**, **sub-shape B** (standalone throwaway
  route — there is no existing app). Use the `?variant=` URL-param + floating
  bottom switcher-bar convention from the skill.
- One command to run. A small Vite/React app is reasonable here given `diff2html`;
  keep it throwaway (no tests, no abstractions).
- No real fetch/mutations — actions just update in-memory UI state.

## When done

Capture the winning treatment and why in `NOTES.md` in this directory (question:
"what should the multi-skill diff review surface look/feel like?"). Leave a
placeholder verdict if the user hasn't responded yet.
