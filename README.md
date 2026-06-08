# skills

A personal, version-controlled **fork** of my Claude Code skills. I sync it across
my devices manually and modify the skills to fit my own workflow.

## Layout

```
skills/        # the skills themselves — a drop-in ~/.claude/skills/ directory
app/           # Steve — macOS menu-bar app that syncs skills onto a device
scripts/       # tooling (quick_validate.py — advisory strict lint)
docs/adr/      # architecture decision records
CONTEXT.md     # domain glossary
PROVENANCE.md  # registry of sources skills were drawn/derived from (attribution)
```

`skills/` is structured to be a valid `~/.claude/skills/` directory: each
subdirectory is one skill containing a `SKILL.md`. Syncing it onto a device is
handled by **Steve** (`app/`), a macOS menu-bar app that treats this repo as
**Origin** and installs skills into `~/.claude/skills/` over public HTTPS — no git
or auth required. See [ADR 0003](docs/adr/0003-sync-devices-via-menu-bar-app-over-public-https.md)
and [ADR 0004](docs/adr/0004-steve-native-swiftui-agent-with-embedded-web-diff.md).

> **Status / prerequisite:** Steve isn't built yet (`app/` is not yet scaffolded),
> and the default branch has **not been pushed to GitHub**, so Origin is currently
> empty. Until it's pushed, any cached skill would read as *Removed on origin* —
> that's expected, not a bug. Push the default branch before running Steve.

## Validity bar

A skill must be **runtime-valid** — i.e. the Claude Code runtime loads it
(`SKILL.md` with `name` + `description`, kebab-case `name` matching the directory,
relative supporting-file paths). See [ADR 0002](docs/adr/0002-runtime-validity-bar.md).

`scripts/quick_validate.py` is a *stricter* advisory lint for skills you intend to
share publicly. Three skills here (`handoff`, `setup-skills`,
`zoom-out`) intentionally fail it because they use real runtime frontmatter keys
it doesn't allow — that's expected, not a defect.

```bash
python3 scripts/quick_validate.py skills/<skill-name>
```

## Provenance

These skills were seeded from external sources and hard-forked — no upstream
tracking. See [PROVENANCE.md](PROVENANCE.md) and
[ADR 0001](docs/adr/0001-hard-fork-skills.md).
