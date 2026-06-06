# Sync devices via an in-repo menu-bar app over public HTTPS (no git, no auth)

We are reversing the "syncing is a manual step" posture: a menu-bar app ("Steve",
under `app/`) automates getting the fork onto a device's `~/.claude/skills/`. It
treats this repo's GitHub default branch as **Origin** and reads it over **plain
public HTTPS — no git, no authentication** — so it works on a device with no
clone present. Change is detected with a cheap unauthenticated commit-SHA probe
(GitHub API), and content is fetched as the codeload tarball only when the SHA
moves.

We chose this over a git-clone/`git pull` model or an authenticated API to keep
the app dependency-free (no git binary, no tokens, no keychain) and decoupled
from any working checkout. The accepted trade-offs: Origin must stay a **public**
repo, and we lean on the anonymous API rate limit (60 req/hr per IP, shared) for
the probe — both acceptable for a personal, single-public-repo tool.

## Consequences

- Making the repo private would break Steve; that's a deliberate constraint.
- The app keeps its own **Cache** (last-seen Origin) separate from the working
  clone; per-skill change detection is a content diff of the tarball against the
  Cache, not a git operation.
