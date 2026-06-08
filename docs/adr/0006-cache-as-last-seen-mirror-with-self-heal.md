# Cache is a last-seen mirror; skill state is content-derived, with self-heal

Each device keeps a **Cache** at `~/Library/Application Support/Steve/cache/` — a
literal mirror of Origin's `skills/` tree (so per-skill comparison is a plain
directory content diff) plus a small metadata file (last-seen commit SHA, per-skill
**skip** state, last-check timestamp). A managed skill's state is derived from three
content comparisons — **O** = Origin, **C** = Cache, **S** = skills directory:

- **Up-to-date** `S == O` · **Update available** `O ≠ C and S ≠ O` ·
  **Skipped** `C == O and S ≠ O` · **Removed on origin** (cached/installed, gone from O).

The attention signal is driven by **O ≠ C** (a change since last seen); the diff
shown is **S vs O** (what installing would actually change). **Skip** copies O→Cache
only; **Update** copies O→Cache *and* O→skills directory. For Removed on origin,
Update deletes from both and Skip records the absence in the Cache.

## Why these rules (the non-obvious parts)

- **Self-heal**: whenever `S == O`, treat the skill as Up-to-date *and* silently set
  `C ← O`. This lets a device that was hand-synced (or synced before Steve existed)
  land correctly without a separate "adopt baseline" step.
- **First run** needs no special mode: an empty Cache plus self-heal means skills
  already matching Origin go green automatically, and everything else shows as
  **Update available** — exactly the right result for a fresh device (bulk-install
  via "Select all new" → Update). We deliberately reject a baseline/onboarding mode
  because it would risk silently accepting a *stale* install as current.
- **Foreign skills** (present in the skills directory, never on Origin, never cached)
  are ignored entirely — the app's universe is `Origin ∪ Cached`.
- **Skip is per Origin version, not a permanent ignore.** Because Skipped means
  `C == O`, a *later* Origin change makes `C ≠ O` again and the skill returns to
  **Update available**. Skip means "not this change, for now"; a fresh upstream
  change is new information worth re-surfacing. (A true "ignore this skill forever"
  would be a separate explicit feature, not an overload of Skip.)
- **Skill identity is the directory name** (ADR 0002 keeps `name` == directory). A
  rename on Origin therefore surfaces as the old directory **Removed on origin** plus
  the new directory **Update available** (a fresh install) — there is no rename/move
  detection.

## Review-session consistency (Origin moving mid-review)

The Review window operates on an **immutable Origin snapshot** taken when it opens
(at a specific SHA). Background checks keep refreshing "last checked" but never alter
or close an open Review window. **Update and Skip re-validate the live Origin SHA at
commit time**: if Origin still matches the snapshot, the action proceeds; if it has
moved, the action is blocked with a "Origin changed since you opened this — reload to
re-review" prompt that refreshes the diffs. This guarantees you can never install
content you did not actually see, without yanking the UI out from under a review in
progress.

## Consequences

- The Cache is authoritative for "what have I seen?", independent of the working
  git clone; it is re-derivable from Origin if lost (Skip state is the only thing
  not recoverable from Origin).
- **On cache/metadata corruption** (unparseable metadata or a torn cache tree),
  rebuild the Cache from Origin rather than refusing to run. The only loss is
  per-skill skip state (skipped skills reappear as Update available); self-heal then
  re-derives every state from the S-vs-O comparison.
