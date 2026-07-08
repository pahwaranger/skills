# Ticket tracker: GitHub

Tickets and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create a ticket**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read a ticket**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List tickets**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on a ticket**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`. The label must already exist — `gh` errors when adding a missing one. See `triage-labels.md` for the triage labels and how to (re)create them.
- **List existing labels**: `gh label list --json name --jq '.[].name'`. Create a missing one with `gh label create "<name>" --color <hex> --description "..."` (never `--force`).
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## When a skill says "publish to the ticket tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
