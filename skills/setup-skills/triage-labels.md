# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's ticket tracker.

| Canonical role             | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this ticket  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## (Re)creating these labels

These labels must exist in the tracker before `triage`/`to-tickets` can apply them (`gh`/`glab` don't auto-create labels). To create any that are missing, run — for each label string in the table above — `gh label create "<label>" --color <hex> --description "<meaning>"` (GitHub) or `glab label create --name "<label>" --color <hex> --description "<meaning>"` (GitLab), using these colors: `needs-triage` `fbca04`, `needs-info` `d93f0b`, `ready-for-agent` `0e8a16`, `ready-for-human` `1d76db`, `wontfix` `ffffff`. Creating a label that already exists is a no-op; don't pass `--force`.
