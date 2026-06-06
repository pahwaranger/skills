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
