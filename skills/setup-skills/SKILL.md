---
name: setup-skills
description: Sets up an `## Agent skills` block in AGENTS.md/CLAUDE.md and `docs/agents/` so the engineering skills know this repo's ticket tracker (GitHub or local markdown), triage label vocabulary, and domain doc layout. Run before first use of `to-tickets`, `to-prd`, `triage`, `diagnose`, `tdd`, `improve-codebase-architecture`, or `zoom-out` — or if those skills appear to be missing context about the ticket tracker, triage labels, or domain docs.
disable-model-invocation: true
---

# Setup Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Ticket tracker** — where tickets live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown ticket tracker convention is already in use

### 2. Present findings and ask

Summarise what's present and what's missing. Then walk the user through the three decisions **one at a time** — present a section, get the user's answer, then move to the next. Don't dump all three at once.

Assume the user does not know what these terms mean. Each section starts with a short explainer (what it is, why these skills need it, what changes if they pick differently). Then show the choices and the default.

**Section A — Ticket tracker.**

> Explainer: The "ticket tracker" is where tickets live for this repo. Skills like `to-tickets`, `triage`, `to-prd`, and `qa` read from and write to it — they need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub** — tickets live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab** — tickets live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown** — tickets live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.) — ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

**Section B — Triage label vocabulary.**

> Explainer: When the `triage` skill processes an incoming ticket, it moves it through a state machine — needs evaluation, waiting on reporter, ready for an AFK agent to pick up, ready for a human, or won't fix. To do that, it needs to apply labels (or the equivalent in your ticket tracker) that match strings *you've actually configured*. If your repo already uses different label names (e.g. `bug:triage` instead of `needs-triage`), map them here so the skill applies the right ones instead of creating duplicates.

The five canonical roles:

- `needs-triage` — maintainer needs to evaluate
- `needs-info` — waiting on reporter
- `ready-for-agent` — fully specified, AFK-ready (an agent can pick it up with no human context)
- `ready-for-human` — needs human implementation
- `wontfix` — will not be actioned

Default: each role's string equals its name. Ask the user if they want to override any. If their ticket tracker has no existing labels, the defaults are fine.

**Once the vocabulary is settled, offer to pre-create the labels.** This is the last thing Section B does, before moving on to Section C.

> Explainer: `gh` and `glab` do **not** auto-create labels — applying a label that doesn't exist errors out, which is exactly what would break `triage` and `to-tickets` the first time they try to move a ticket. So the labels need to exist in the tracker before those skills run. I can create the five triage labels for you now.

Ask a **yes/no** question. Pre-creating is the **recommended default**, but it's genuinely declinable — if the user says no, record the mapping only (as today) and create nothing. Behave per the tracker chosen in Section A:

- **GitHub / GitLab** — offer to create the labels now and, on "yes", run the create commands yourself (see below). This is the recommended default.
- **Local markdown** — skip this entirely. There is no label system; triage state is a `Status:` line in the ticket file, so there are no labels to create and **no prompt appears**.
- **Other / freeform** (Jira, Linear, …) — don't offer to run anything (the CLI is unknown). Instead, note that the generated `docs/agents/ticket-tracker.md` will carry a one-line recommendation to pre-create the five labels in that tool (see step 4).

**Creating the labels (GitHub / GitLab, on "yes"):**

Use the **description** for each role verbatim from the "Meaning" column of the table in [triage-labels.md](./triage-labels.md), and this fixed color palette. Colors and descriptions are applied **only to labels you newly create** — never to ones that already exist.

| role              | color    |
| ----------------- | -------- |
| `needs-triage`    | `fbca04` |
| `needs-info`      | `d93f0b` |
| `ready-for-agent` | `0e8a16` |
| `ready-for-human` | `1d76db` |
| `wontfix`         | `ffffff` |

**List-then-create-missing.** First list the tracker's existing labels, then create only the ones that are absent:

- GitHub: `gh label list --json name --jq '.[].name'` to list; `gh label create <name> --color <hex> --description "<desc>"` for each missing label.
- GitLab: `glab label list -F json` (parse the `name` fields) to list; `glab label create --name <name> --color <hex> --description "<desc>"` for each missing label.

Match against the label **strings from the Section B mapping** (which may be custom, e.g. `bug:triage`), not the canonical role names. **Never** pass `--force`; **never** overwrite the color or description of a label that already exists — if a role is mapped to an existing custom label, leave it untouched. When done, report the result, e.g. "created 3, skipped 2 that already existed".

**Graceful degradation.** Label provisioning must **never** gate setup completion. If the CLI is missing or unauthenticated, or a create command fails:

- Tell the user what went wrong (e.g. `glab` not installed, or not authenticated).
- Emit the **exact** create commands so they can run them later.
- Continue with the rest of setup anyway — the `## Agent skills` block and all three docs files still get written.

**Section C — Domain docs.**

> Explainer: Some skills (`improve-codebase-architecture`, `diagnose`, `tdd`) read a `CONTEXT.md` file to learn the project's domain language, and `docs/adr/` for past architectural decisions. They need to know whether the repo has one global context or multiple (e.g. a monorepo with separate frontend/backend contexts) so they look in the right place.

Confirm the layout:

- **Single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. Most repos are this.
- **Multi-context** — `CONTEXT-MAP.md` at the root pointing to per-context `CONTEXT.md` files (typically a monorepo).

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/ticket-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`

Let them edit before writing.

### 4. Write

**Pick the file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create — don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's already there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Ticket tracker

[one-line summary of where tickets are tracked]. See `docs/agents/ticket-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Then write the three docs files using the seed templates in this skill folder as a starting point:

- [ticket-tracker-github.md](./ticket-tracker-github.md) — GitHub ticket tracker
- [ticket-tracker-gitlab.md](./ticket-tracker-gitlab.md) — GitLab ticket tracker
- [ticket-tracker-local.md](./ticket-tracker-local.md) — local-markdown ticket tracker
- [triage-labels.md](./triage-labels.md) — label mapping
- [domain.md](./domain.md) — domain doc consumer rules + layout

For "other" ticket trackers, write `docs/agents/ticket-tracker.md` from scratch using the user's description. Because the skill can't drive an unknown CLI, include a one-line recommendation in that file to pre-create the five triage labels (from `triage-labels.md`) in that tool before running `triage` or `to-tickets` — don't run any command yourself.

### 5. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Mention they can edit `docs/agents/*.md` directly later — re-running this skill is only necessary if they want to switch ticket trackers or restart from scratch.
