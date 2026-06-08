# Prototype: Steve — Settings tab

Build a throwaway visual prototype of **Steve's Settings tab**, using the
`/prototype` skill (UI branch). Goal: lock in the form layout and how dependent
controls are grouped before the SwiftUI build.

## About Steve (shared context — you are starting cold)

Steve is a macOS **menu-bar agent** (native SwiftUI in production; no Dock tile)
that syncs a personal fork of Claude Code skills onto a device, treating a public
GitHub repo as **Origin** and installing into `~/.claude/skills/`. It checks for
changes on a timer and surfaces them via a red menu-bar icon.

This is a **throwaway** web prototype for look-and-feel only. No persistence —
controls just flip in-memory state.

## Locked decisions (constraints — do NOT change these)

Settings is the **second tab** of a two-tab window (the other is the Review tab,
prototyped separately). Render the window chrome — title bar and the two tabs —
with **Settings** active and consistent with the Review prototype's chrome.

Controls, with their defaults and behaviour:

1. **Launch at login** — toggle. Default **on**.
2. **Automatic checks** — toggle. Default **on**. When **off**, only the manual
   "Check for updates" button (in the dropdown) triggers a check.
3. **Minutes between checks** — numeric field. Default **60**. **Disabled/greyed
   out when Automatic checks is off** (this dependency is the main thing to get
   right visually).
4. **Default diff view** — split vs. unified. Default **split**.

No other settings exist (Origin URL, cache path, etc. are hardcoded and not
exposed). Keep the surface to exactly these four controls.

## What the variants should explore (this is the open question)

The control set is locked; vary the **layout and grouping** so the user can pick
the feel. **2 variants** is enough here (the surface is small):

- A simple flat vertical form (label + control rows) vs. grouped sections with
  short explanatory captions (e.g. "Syncing" group containing automatic checks +
  interval; "General" containing launch-at-login + default diff view).
- Make the **dependent-control behaviour** clearly legible: when **Automatic
  checks** is off, **Minutes between checks** must visibly disable. Try different
  treatments (greyed inline vs. collapsed/hidden vs. nested-indented under the
  toggle) across the variants.

Native-macOS settings-pane feel; light/dark aware.

## How to build it

- Use the `/prototype` skill, **UI branch**, **sub-shape B** (standalone throwaway
  route — there is no existing app). Use the `?variant=` URL-param + floating
  bottom switcher-bar convention from the skill.
- One command to run; plain HTML/CSS/JS or a tiny Vite app. Throwaway — no tests,
  no abstractions. Toggling controls only updates in-memory state.

## When done

Capture the winning layout and why in `NOTES.md` in this directory (question: "what
should the Settings tab look like, and how should the disabled-interval dependency
read?"). Leave a placeholder verdict if the user hasn't responded yet.
