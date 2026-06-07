---
name: grill-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan against their project's language and documented decisions.
---

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.

Before asking the first question, survey the full design space and estimate how many questions you expect to ask. Tell the user upfront: "I have ~N questions for you." Then prefix each question with its sequence position: **Question X of ~N:**. Revise the estimate whenever a branch opens or closes — say so briefly when you do ("Adding ~2 questions after that answer — now ~N total.").

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

### Offer prototype prompts for unresolved design questions

When a design question cannot be resolved by reasoning alone — the answer depends on how the code actually feels, or how a UI actually renders — offer to create a prototype prompt that another agent can implement.

Present it as one of the options when the question is first raised. Example: "We could (a) decide now, (b) defer, or (c) prototype it — I can write a prompt another agent can pick up."

If the user chooses to prototype, do the following:

1. **Pick a slug** — a short kebab-case name for what is being explored (e.g. `order-state-machine`, `checkout-flow-variants`).
2. **Create the directory** `prototypes/<slug>/` at the project root. Create `prototypes/` itself if it doesn't exist.
3. **Write `prototypes/<slug>/PROMPT.md`** with everything a cold agent needs to build the prototype and record results. The file must contain:
   - **Question** — the specific design question the prototype must answer, in one sentence.
   - **Context** — the relevant domain terms (from `CONTEXT.md`), constraints, and decisions already made in this grilling session.
   - **Prototype type** — `logic` (terminal/state-machine) or `ui` (visual variants), with a one-line justification.
   - **What to build** — a concrete description of the prototype: the states/transitions to exercise, or the UI variants to render.
   - **How to record results** — what the agent should write back when done: the answer to the question, the verdict (adopt / reject / inconclusive), and any follow-up questions that arose.
4. **Surface the path** to the user so they know where the prompt lives and can hand it off.

Do not start the prototype yourself — the purpose of this step is to create a handoff artifact.

5. **Ask whether to pause or continue.** After surfacing the path, ask: "Do you want to pause here while you review the prototype, or should I keep going and come back to this at the end?"

   - **Pause** — tell the user you're waiting and to let you know when the prototype is done. When they return, read the prototype's results (check `prototypes/<slug>/` for any output or notes the agent left), summarise what you learned, then resume the questions from where you left off.
   - **Continue** — note that the questions whose answers depend on the prototype outcome are deferred (tell the user: "I'll park those and come back to them at the end"). Adjust the running question count to exclude the deferred questions for now, then proceed with all remaining independent questions. Once those are done, flag the return: "The prototype question is still open — revisiting it now." and work through the deferred questions as if they were next in the original sequence.

</supporting-info>
