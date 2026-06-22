# Fixture mode ships in the Release binary, gated by a launch argument

Steve's actionable skill surfaces — **Update available**, **Removed on origin**,
**Skipped**, and the UI that only renders when such skills exist (the grouped
sidebar, the materialising toolbar, the pane-header state chip, the per-file diff
cards) — cannot be verified when the live app has nothing to act on, which is the
normal steady state. Rather than deliberately desync a real skill against Origin to
see them, Steve has a **fixture mode**: an opt-in composition that serves a canned
**fixture origin** through the real `OriginClient → Cache → StateEngine →
ReviewSession` pipeline and reproduces all four states at once. Fixture mode is
**gated by a launch argument** (`--fixtures`, or `STEVE_FIXTURES=1`) and is
**present in the Release binary** — not compiled out with `#if DEBUG` — so the
shipped, signed `.app` can be launched in fixture mode for screenshot verification.
A normal launch passes neither and is byte-for-byte unaffected.

## Why ship it in Release (the non-obvious part)

The obvious instinct is to wrap fixture composition in `#if DEBUG` so it physically
cannot exist in a user's binary. We deliberately did not. The verification this
unblocks must run against the **same Release artifact** users get — window chrome,
signing, `LSUIElement` accessory behaviour, the real menu-bar runtime; a DEBUG-only
build would verify a different thing, and an earlier verification pass stalled
precisely because the freshly-built accessory app couldn't be driven. Gating on a
launch argument keeps the shipped binary inert under normal use (`open Steve.app`
passes no such argument) while letting a developer — or the local XCUITest lane —
opt in explicitly.

## Why it is safe to ship fake-data composition

Fixture mode fakes only the **network transport** and the **starting on-disk
state**; everything downstream is the real code path. State is **derived, not poked
into the model** — the `private(set)`/`internal(set)` access on `lastDerivedState`
and `reviewSession` is untouched, honoring ADR 0006/0007 (the fixture goes through
the same derivation; the UI state is never faked past the model). Hard isolation
guardrails apply: fixture mode never reads, writes, or mutates the real Skills
directory, the real backups directory, or `UserDefaults.standard`. It composes
ephemeral temp sandbox directories and a throwaway defaults suite, enforced by a
path-isolation precondition and a unit test. The only thing that ships is a
transport stub plus sandbox-seeding code that does nothing unless the flag is set.

## Considered options

- **`#if DEBUG` only (rejected):** compiled out of Release entirely — the strongest
  guarantee a user can never trigger it, but it cannot screenshot a Release build,
  which is the whole point.
- **Launch-arg in Release (chosen):** the shipped binary contains inert fixture
  composition, opt-in via `--fixtures` / `STEVE_FIXTURES=1`. Screenshot-able;
  relies on the flag never being set in a normal launch (it isn't).

## Consequences

- The Release binary contains the fixture transport + sandbox-seeding code; it is
  inert unless the launch flag is present.
- The local XCUITest lane depends on `--fixtures` being available in the Release
  build; removing fixture mode would break that lane.
- The **preview** path is deliberately different: SwiftUI `#Preview` providers seed
  `DerivedState`/`ReviewSession` directly (a lower-fidelity route used only for
  visual iteration), and that direct-seed seam stays `#if DEBUG` — compiled out of
  Release. Only the derive-through-the-pipeline fixture mode ships.
- If a future requirement demands the shipped binary contain zero fixture code, the
  fallback is to revert fixture mode to `#if DEBUG` and accept the loss of
  Release-build screenshot verification.
