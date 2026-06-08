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
- **Cadence & triggers**: Steve checks on **app launch**, on an **hourly timer**
  (interval configurable, default 60 min; an "automatic checks" toggle disables the
  timer), and on the manual **Check for updates** button. Checks are **single-flight**
  — at most one in flight at a time; a trigger that fires during a running check is
  ignored (not queued or run concurrently), and the manual button is disabled while a
  check is active. This keeps the icon's single-pulse model honest.
- **Conditional requests**: the SHA probe sends `If-None-Match` with a stored ETag.
  GitHub returns `304 Not Modified` when nothing changed, and **304s do not count
  against the rate limit** — so the usual no-change probe is effectively free. The
  ETag is stored in the cache metadata alongside the SHA.
- **Error taxonomy** (all non-destructive — keep last state/Cache):
  - Network down / timeout / 5xx → `Couldn't reach origin · checked Nh ago`; retry next tick.
  - **403 rate-limited** (`X-RateLimit-Remaining: 0`) → `GitHub rate limit reached · retries H:MM`;
    **back off until `X-RateLimit-Reset`**, then resume — do not hammer.
  - 404 repo not found / private → `Origin not found — check repo`; config error, slow retry, no spamming.
  - Tarball corrupt / extract fail → `Origin fetch failed · checked Nh ago`; transient, retry next tick.
- **Default-branch resolution**: the "open on GitHub" links and any branch-qualified
  URL use the repo's **resolved default branch** (read from the API), not a hardcoded
  `main`/`master` literal.
