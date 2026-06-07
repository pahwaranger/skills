# Skills Store

A personal, version-controlled fork of Claude Code skills, synced across the
user's devices. Skills are drawn or derived from external sources, or authored
from scratch, then modified to fit the user's own workflow.

## Language

**Skill**:
A self-contained Claude Code capability — a directory holding a `SKILL.md` plus
optional supporting files — that this repo version-controls and syncs.
_Avoid_: command, plugin, tool.

**Fork**:
What this repo is. A divergent personal copy of skills the user owns outright and
modifies freely, not a verbatim mirror of any origin.
_Avoid_: mirror, clone, backup.

**Source**:
An external origin a skill was drawn or derived from. Every source the repo has
used is recorded for attribution; the repo keeps no live tie to any of them.
_Avoid_: upstream, remote.

**Ticket**:
A unit of work to be completed, as referenced by the skills. The canonical term
for the work-item concept.
_Avoid_: issue — except when naming a platform's native feature (GitHub/GitLab
"issues", the `gh issue` / `glab issue` CLI), which keep their real names.

### Syncing

**Origin**:
The authoritative copy of the fork — the `skills/` directory on the default
branch of the GitHub repo (`pahwaranger/skills`). The sync app reads it over
plain public HTTPS, requiring neither git nor authentication, and works on a
device that has no git clone present.
_Avoid_: remote, upstream, server.

**Cache**:
A private copy of the origin that the sync app maintains, representing the last
origin state the user has seen and acted on. Distinct from the working git clone.
_Avoid_: snapshot, mirror.

**Skills directory**:
The live `~/.claude/skills/` directory that the Claude Code runtime actually
loads on a device. What the sync app installs into.
_Avoid_: target, destination, install dir.

**Managed skill**:
A skill the sync app governs — one that is, or has been, on origin (i.e. the app
holds a cache entry for it). The app's universe is the union of origin skills and
cached skills.

**Foreign skill**:
A skill present in the skills directory that has never been on origin and the app
has never cached. The app ignores it entirely — never lists, counts, or touches it.
_Avoid_: external, third-party, unmanaged (as a distinct state).

The four sync states a managed skill can be in (S = skills directory, C = cache,
O = origin):

**Up-to-date**:
Installed matches origin (S == O). Not actionable.

**Update available**:
Origin moved since last seen and is not installed (O ≠ C and S ≠ O). The "new,
unseen" state — drives the attention indicator.

**Skipped**:
The origin change was seen and deferred (C == O) but is not installed (S ≠ O).
Acknowledged, not actionable by default.

**Removed on origin**:
A cached/installed skill that origin no longer has. Treated as a change to sync.

### Steve UI surfaces

**Review tab**:
The primary window tab where the user inspects and acts on pending skill changes.
Contains the sidebar and the diff pane. Design locked; see
`prototypes/review-diff/NOTES.md`.
_Avoid_: sync window, update window.

**Settings tab**:
The secondary window tab for app preferences (launch-at-login, check interval,
default diff view). Design locked; see `prototypes/settings/NOTES.md`.

**Sidebar** (Review tab):
The left panel of the Review tab. Lists all managed skills grouped by state
(Removed on origin → Update available → Skipped → Up-to-date, alpha within group).
Contains a sticky **action header** at the top and a scrollable **skill list** below.
_Avoid_: skill list (that's the scrollable region inside the sidebar, not the sidebar itself).

**Action header**:
The sticky strip pinned to the top of the Review-tab sidebar. Holds the
3-state select toggle, Update N, and Skip N buttons — always visible without scrolling.

**Diff pane**:
The right panel of the Review tab. Shows the selected skill's per-file diffs as
collapsible file cards. Hosts the pane header (skill name + Split/Unified toggle)
and the materialising selection toolbar.

**File card**:
A collapsible section in the diff pane representing one file within a skill's diff.
Header shows: filename, status pill (Modified/Added/Deleted), line counts (+N/−N).
Open by default; clicking the header collapses/expands.

**Materialising toolbar**:
A selection-action bar that appears in the diff pane only when ≥ 1 skill is checked.
Contains the 3-state toggle, Update, Skip, and a ✕ to dismiss.
_Avoid_: floating toolbar (it's sticky, not floating).

**3-state select toggle**:
A button that cycles the bulk selection through three states:
Select all actionable → Select new only (Update available + Removed; excludes Skipped) → Deselect all.
Present in both the action header (always visible) and the materialising toolbar.
