# Review venue is decoupled from the ticket tracker

The skills support four ticket trackers (GitHub, GitLab, local markdown, custom such as Jira/Linear), and it is tempting to assume the ticket's home is also where its code gets reviewed — i.e. a GitHub issue implies a GitHub PR. That assumption is false: a repo can keep tickets in Jira but push PRs to GitHub, or keep tickets as local markdown with no remote at all. So `implement-afk` treats *where a ticket lives* and *where its code is reviewed and merged* as two independent axes — the tracker is read from `docs/agents/ticket-tracker.md`, while the review/merge venue is derived separately from the git remote (GitHub → PR, GitLab → MR, no remote → local feature-branch loop).

## Considered Options

- **Tie venue to tracker type** — simplest mapping, but cannot express decoupled setups (Jira tickets + GitHub PRs) and has no answer for a local tracker that happens to have a GitHub remote.
- **Require a PR/MR remote always** — drops local/no-remote support entirely.

## Consequences

The review *loop* is identical across venues; only the communication medium changes (PR review comments / MR notes / coordinator-relayed for local). A future `setup-skills` revision may want to capture the code-host as its own configured axis rather than leaving `implement-afk` to infer it from `git remote`.
