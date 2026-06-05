# Runtime validity is the bar, strict lint is advisory

A skill in this repo must be valid in the sense that the **Claude Code runtime
loads it** — a `SKILL.md` with `name` + `description` frontmatter, kebab-case
`name` matching its directory, supporting files referenced relatively. That is
the enforced contract.

The strict validator vendored at `scripts/quick_validate.py` (from skill-creator)
uses a *narrower* allow-list intended for shareable, model-invocable skills. It
rejects frontmatter keys the runtime accepts — `disable-model-invocation`
(`setup-skills`, `zoom-out`) and `argument-hint` (`handoff`). Those
keys do real work here (they make those skills user-invoke-only), so we keep them
and treat the strict validator as an **advisory lint**, run per-skill only when
preparing one to share. Do not strip those keys to make the linter pass — that
silently breaks intended behavior.
