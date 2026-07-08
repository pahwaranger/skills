---
name: to-tickets
description: Break a plan, spec, or PRD into independently-grabbable tickets on the project ticket tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into tickets, create implementation tickets, or break down work into tickets.
---

# To Tickets

Break a plan into independently-grabbable tickets using vertical slices (tracer bullets). Each ticket will be implemented by a separate subagent using the `/tdd` skill — size and sequence accordingly.

The ticket tracker and triage label vocabulary should have been provided to you — run `/setup-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a ticket reference (ticket number, URL, or path) as an argument, fetch it from the ticket tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** tickets. Each ticket is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

#### Sizing for agentic TDD implementation

Each ticket will be picked up cold by a fresh subagent running `/tdd`. Size and sequence with this in mind:

**Context budget**: A subagent implementing a ticket will spend context exploring the codebase, writing tests, writing code, and iterating. Aim for tickets that fit comfortably within ~30–40% of a context window — a focused behavior or capability, not a full subsystem. If a slice would require touching 5+ modules or writing 10+ tests, split it.

**Test-first sequencing**: Tests are one of the primary deliverables, not a side effect. The first ticket (or first few tickets) in a sequence should establish the test harness and write tests for the foundational behaviors. Later tickets build on that test infrastructure. Never push test creation to the end.

**Handoff hygiene**: Each ticket must leave the codebase in a clean, mergeable state — all tests passing, no stubs that break the build. The next subagent picks up cold; it cannot ask about in-progress work. The ticket description is the only context it gets.

**Dependency isolation**: A subagent can only work on what's merged and visible in the codebase. Keep dependencies explicit and linear where possible — parallel-capable slices are fine, but only when they touch truly independent areas with no shared interfaces.

**Interface contracts before implementation**: If a ticket introduces a new interface that downstream tickets will use, that interface definition (type, schema, API shape) must be in the acceptance criteria — not left implicit. Downstream agents write tests against the contract before implementation exists.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the ticket tracker

For each approved slice, publish a new ticket to the ticket tracker. Use the ticket body template below. These tickets are considered ready for AFK agents, so publish them with the correct triage label unless instructed otherwise.

**If applying a triage label fails because the label doesn't exist** (e.g. `gh`/`glab` reject an unknown label — this does not apply to the local-markdown tracker, which has no labels), **stop** and tell the user to run `/setup-skills` to create the triage labels, then retry. Do not create the label yourself — label creation is owned by `setup-skills`.

Publish tickets in dependency order (blockers first) so you can reference real ticket identifiers in the "Blocked by" field.

<ticket-template>
## Parent

A reference to the parent ticket on the ticket tracker (if the source was an existing ticket, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Behaviors to test

List the specific behaviors the implementing agent should verify, in priority order. These become the TDD loop's agenda — the agent writes one test per behavior before implementing it. Put the most critical or foundational behavior first (it becomes the tracer bullet).

- Behavior 1 (tracer bullet — implement this first)
- Behavior 2
- Behavior 3

## Acceptance criteria

- [ ] All behaviors above are covered by passing tests
- [ ] Criterion specific to this slice
- [ ] Criterion specific to this slice
- [ ] No regressions in existing tests
- [ ] Codebase is in a clean, mergeable state (no broken stubs, no skipped tests)

## Interface contracts

If this ticket introduces types, schemas, or API shapes that downstream tickets depend on, define them here. Downstream agents will write tests against these contracts before the implementation exists.

(Omit this section if no downstream tickets depend on new interfaces introduced here.)

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

## Implementation notes

Brief notes to help the implementing agent orient quickly — which existing modules are most relevant, what the key design constraint is, or what a good tracer bullet looks like for this slice. Keep it short; the agent will explore the codebase.

</ticket-template>

Do NOT close or modify any parent ticket.
