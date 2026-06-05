# Snapshot-and-own externally sourced skills; no upstream tracking

Skills brought in from outside this repo — whether copied wholesale or derived
from someone else's work — are **hard-forked**: we own them outright, modify them
freely to fit the user's workflow, and deliberately maintain **no** live merge
relationship with any source. The obvious path for forked material is to keep it
synced with its origin; we reject that as a standing policy because heavy local
divergence makes ongoing merges conflict-prone for little payoff, and that upkeep
rots.

The trade-off accepted: we forgo automatic upstream fixes. To recover a specific
fix later, diff the single skill against its source by hand.

This is a policy for *all* sources, present and future. Every source we draw from
is recorded in `PROVENANCE.md` for attribution and so that manual diff is possible.
