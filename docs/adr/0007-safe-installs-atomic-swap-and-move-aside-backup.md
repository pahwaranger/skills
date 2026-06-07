# Safe installs: atomic per-skill swap with a move-aside backup

Update and Removed-on-origin actions mutate the live `~/.claude/skills/` directory,
which Claude Code loads at runtime, so installs are made **crash-safe** rather than
written in place. Each skill is installed atomically: write the new directory to a
temp location, then swap it into place, and **update the Cache only after the swap
succeeds**. A bulk Update is a loop of these per-skill swaps — if one fails (network,
disk), the rest still succeed and the failed skill stays in its prior state.

Before any overwrite or delete, the replaced/removed directory is **moved aside**
into `~/Library/Application Support/Steve/backups/<timestamp>/` and retained for
**7 days**, then pruned. Even though the skills directory is a pure consumption
target (authoring happens in the repo clone) and Origin is always re-fetchable, a
surprise bulk Update should never be unrecoverable.

## Why

- Atomicity prevents a half-written skill that the runtime then fails to load.
- The Cache-after-success ordering keeps "last seen" honest if an install aborts.
- The backup is cheap insurance; because Origin is re-fetchable it never has to be
  permanent, hence the short retention window.
