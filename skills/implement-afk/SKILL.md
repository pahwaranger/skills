---
name: implement-afk
description: Coordinate a team of subagents to implement every open AFK (ready-for-agent) ticket end-to-end — implement with /tdd, review, address feedback, and merge each before moving to the next. Use when the user wants to clear the ready-for-agent backlog, implement all AFK tickets, or run an unattended implementation pass.
argument-hint: "[feature-slug | ticket refs | label] — optional; defaults to all open ready-for-agent tickets"
---

# Implement AFK

Run as a **coordinator** of subagents that implements every open **AFK** ticket — the `ready-for-agent` form of a slice produced by `to-tickets` — one at a time, reviewed and merged, with no human in the loop after kickoff.

The ticket tracker and triage label vocabulary should have been provided to you — run `/setup-skills` if not. You consume the same `docs/agents/ticket-tracker.md` and `docs/agents/triage-labels.md` config that `to-tickets` and `triage` do.

HITL tickets and the `ready-for-human` role are **never** picked up here.

## 1. Require git

If the repo is not a git repository, **stop** and ask the user to set up git first. Everything below depends on it.

## 2. Resolve the review-and-merge venue

Where a ticket lives and where its code is reviewed are **independent axes** — derive the venue from the git remote, not from the tracker type (a repo may track in Jira but push PRs to GitHub, or use local-markdown tickets with no remote at all):

| Git remote | Venue | Review medium | Merge |
|---|---|---|---|
| GitHub | Pull Request (`gh pr ...`) | PR review comments | merge the PR |
| GitLab | Merge Request (`glab mr ...`) | MR notes | merge the MR |
| none | local feature branch | coordinator relays review notes (append to the ticket's `## Comments` for the local tracker) | `git merge` into the main branch |

The review **loop** below is identical across venues; only the medium changes.

## 3. Discover and scope

Find the in-scope tickets:

- **Default**: every open ticket carrying the `ready-for-agent` role, per `docs/agents/triage-labels.md`. Filter strictly to AFK — exclude `ready-for-human`, `needs-info`, `needs-triage`, `wontfix`.
- **If an argument is passed**, narrow to it: a feature-slug, an explicit list of ticket refs/numbers, or a label override.
- **Local tracker**: tickets live under `.scratch/<feature-slug>/tickets/`. With a slug, read that directory; without one, scan all `.scratch/*/tickets/` for `Status: ready-for-agent`.

Topologically sort by each ticket's **Blocked by** field (blockers first).

Then **scout each ticket's implementation task**: for every in-scope ticket, run the scout (see _Right-sizing subagents_ under §5) to pick the model + effort its implementer should use. Record the recommendation against the ticket — it's surfaced in the confirmation below and used when the implementer is spawned.

## 4. Confirm before starting (hard gate)

Present the full ordered list of in-scope tickets to the user — each with its scouted **model + effort** recommendation — and get an explicit go-ahead. This is the one checkpoint — after it, the run proceeds unattended.

On approval, **seed the progress task list**: create one task per in-scope ticket (`TaskCreate`), in dependency order, its subject naming the ticket and its scouted model + effort (e.g. `#12 — auth token refresh (sonnet/med)`). Wire each ticket's **Blocked by** into the list with `addBlockedBy`, so dependencies are visible at a glance. This list is how the user monitors the run live — keep it current at every step below. It is ephemeral (it lives with the session); there is no crash-resume.

## 5. Implement each ticket, strictly sequential

**Right-sizing subagents (scout-first).** No subagent is spawned without a scout sizing it first. A scout is a single cheap, fast call (the lowest available tier) that reads the task's inputs — the ticket body for an implementation task, the actual branch diff for a review task — plus the slice of code it touches, and returns a **model tier** (the cheapest of the runtime's tiers — e.g. `haiku`, `sonnet`, `opus`, `fable` — that can do the job reliably) and an **effort level** (low / medium / high), with a one-line justification. Each ticket's implementation task is scouted up front in §3 so it appears in the §4 confirmation; review tasks and any re-spawn are scouted just-in-time, immediately before the spawn, since they depend on the diff that exists at that moment. Spawn each subagent with the model + effort its scout returned.

**Tracking progress.** Keep the task list seeded in §4 live so the user can monitor. When a ticket starts, mark its task `in_progress` (`TaskUpdate`); reflect the **current phase** in its `activeForm` as the ticket advances — e.g. `Implementing #12 (sonnet/med)`, `Reviewing #12 (round 2/3)`, `Merging #12`. At a ticket's terminal state, mark its task `completed` regardless of outcome (the coordinator is done with it) and write the outcome into both the subject and task metadata:

- merged → `Merged #12`
- skipped, needs a human → `⚠ Skipped #12 — draft PR, needs human: <reason>`
- skipped, blocked by a failed blocker → `Skipped #12 — blocked by #11`

For each ticket in dependency order:

1. **Branch** off the freshly-updated main branch (mark the ticket's task `in_progress`).
2. **Implement**: trigger a fresh subagent — using the model + effort from this ticket's up-front scout — that picks up the ticket cold and runs `/tdd`. The ticket body is its only context — do not hand it conversation history.
3. **Review**: scout, then trigger, **two reviewer subagents** with split lenses against the branch diff (size each against the actual diff):
   - **Reviewer A** — correctness + acceptance-criteria coverage: does it build what the ticket specified, with every listed behavior covered by a passing test?
   - **Reviewer B** — test quality + scope/domain fit: are the tests real (not tautological)? Is scope respected (no creep), domain glossary in `CONTEXT.md` honored, relevant ADRs respected, codebase left clean and mergeable?

   Reviewers post feedback through the venue's medium (PR/MR comments, or coordinator-relayed for local).
4. **Address feedback**: the original implementer subagent (keeping its scouted sizing) addresses review feedback over **at most 3 rounds**, re-requesting review each round; re-scout the reviewers before each fresh review round.
5. **Merge gate** — all of:
   - every acceptance-criteria behavior covered by passing tests,
   - the full test suite green locally,
   - both reviewers approve,
   - CI green, if the remote has it.
6. **On pass**: merge. Link the PR/MR to the ticket so the merge auto-closes it (`Closes #N`); for GitLab and the local tracker, close explicitly / set `Status: done` and append a merge note. Mark the ticket's task `completed` (`Merged #12`). Re-base or update main, then move to the next ticket.
7. **On fail** (round cap hit, tests won't pass, or the ticket turns out to need a human): **never merge broken code.** Push the branch and open a **draft** PR/MR (or, on local/no-remote, leave the branch named clearly) with the partial work and an explanation. Leave the ticket open — relabel toward `needs-info` / `ready-for-human` when a human is genuinely needed. Mark the ticket's task `completed` with the skip outcome (`⚠ Skipped #12 — draft PR, needs human: <reason>`). **Skip every ticket Blocked-by it** — mark each of those tasks `completed` as `Skipped — blocked by #12` — then continue with the next independent ticket.

## Provenance

Every agent-authored PR/MR body, review, and ticket comment opens with an AI disclaimer, mirroring `triage`'s convention:

> *Generated by the implement-afk agent.*

## 6. Report

When the run ends, summarize **done** vs **skipped** (with the reason and any draft PR/MR link for each skipped ticket) — this mirrors the final state of the task list.
