// Fake data for the Steve Review prototype.
// Diffs are plausible but invented — just needs to look like real skill files.

export type SkillState = 'removed' | 'update' | 'skipped' | 'uptodate'

export interface FileDiff {
  filename: string   // full path used as key
  shortName: string  // display name (just the filename)
  status: 'modified' | 'added' | 'deleted'
  rawDiff: string
}

export interface Skill {
  id: string
  label: string
  state: SkillState
  files: FileDiff[]
}

// ---------------------------------------------------------------------------
// Diff strings
// ---------------------------------------------------------------------------

const GRILL_SKILL_MD = `diff --git a/grill-with-docs/SKILL.md b/grill-with-docs/SKILL.md
index 3a8f2b1..c9d7e40 100644
--- a/grill-with-docs/SKILL.md
+++ b/grill-with-docs/SKILL.md
@@ -1,7 +1,7 @@
 # Grill with Docs

-Challenge your plan against the existing domain model, sharpen terminology,
-and update documentation inline as decisions crystallise.
+Challenge any design against the canonical domain model — surface unstated
+assumptions, force vocabulary alignment, and lock decisions into docs as they land.

 ## When to use

@@ -13,7 +13,7 @@
 ## Steps

 1. Load CONTEXT.md and all ADRs from docs/adr/.
-2. Ask 5–8 adversarial questions about the plan.
-3. For each answer: update CONTEXT.md or write/amend an ADR.
+2. Ask 7–10 adversarial questions — at least two must challenge vocabulary.
+3. For each settled answer: update CONTEXT.md or write/amend an ADR immediately.
 4. Re-grill any answer that introduces new ambiguity.
 5. Stop when no open questions remain.`

const GRILL_CONTEXT_FORMAT_MD = `diff --git a/grill-with-docs/CONTEXT-FORMAT.md b/grill-with-docs/CONTEXT-FORMAT.md
index 8b3d1c9..f4a7e23 100644
--- a/grill-with-docs/CONTEXT-FORMAT.md
+++ b/grill-with-docs/CONTEXT-FORMAT.md
@@ -18,6 +18,9 @@
 ## Rules

 - One concept per entry; never merge two terms into one bullet.
+- Every term must have a canonical short form used consistently in code.
+- If a term has a well-known industry equivalent, note the mapping explicitly.
+- Deprecated terms belong in a ## Retired section, not deleted.
 - ADR titles must be imperative ("Use X", "Reject Y") — no gerunds.
 - Cross-reference liberally; a term that appears in an ADR should link back.`

const GRILL_EXAMPLES_MD = `diff --git a/grill-with-docs/EXAMPLES.md b/grill-with-docs/EXAMPLES.md
new file mode 100644
--- /dev/null
+++ b/grill-with-docs/EXAMPLES.md
@@ -0,0 +1,30 @@
+# Grill with Docs — Examples
+
+These examples show the kind of adversarial questions the skill generates.
+
+## Example 1 — Auth redesign
+
+**Plan:** Replace session tokens with JWTs to support horizontal scaling.
+
+**Questions generated:**
+
+- "CONTEXT.md defines *session* as a server-side object. JWTs are client-side.
+  Which term wins? Update the glossary before continuing."
+- "ADR-004 says 'reject stateless tokens' — is this plan overriding that decision,
+  or have the constraints changed? State it explicitly."
+- "You said 'horizontal scaling' but CONTEXT.md has no definition for that term.
+  Add one, or use a term that is already defined."
+
+## Example 2 — New event pipeline
+
+**Plan:** Add a Kafka topic for user-action events.
+
+**Questions generated:**
+
+- "Is *event* the right term? CONTEXT.md uses *action* for user-initiated changes
+  and *event* for system-generated state changes. Which is this?"
+- "ADR-011 mandates all new topics go through Platform team review.
+  Has that happened, or does this plan need to gate on it?"
+- "The word *pipeline* appears three times but is not in CONTEXT.md.
+  Define it or replace it with a term that already exists."`

const TDD_SKILL_MD = `diff --git a/tdd/SKILL.md b/tdd/SKILL.md
index 7c4a3b2..2e8f1d0 100644
--- a/tdd/SKILL.md
+++ b/tdd/SKILL.md
@@ -1,8 +1,8 @@
 # TDD

-Red-green-refactor loop for building features or fixing bugs test-first.
+Strict red-green-refactor loop for features and bug fixes, with integration
+test coverage as a first-class goal alongside unit tests.

 ## When to use

-When the user asks for TDD, mentions red-green-refactor, or wants a test harness
-before implementation begins.
+When the user asks for TDD, mentions red-green-refactor, wants integration tests,
+or asks for test-first development on any non-trivial feature.

 ## Steps
@@ -13,5 +13,5 @@
 2. Write the minimal implementation that makes it pass (green).
 3. Refactor without letting tests go red.
 4. Repeat until the feature is complete.
-5. Summarise the test coverage added.
+5. Run the full test suite and confirm no regressions before summarising.`

const TO_ISSUES_SKILL_MD = `diff --git a/to-issues/SKILL.md b/to-issues/SKILL.md
index 4f8e2a7..9c1b3d5 100644
--- a/to-issues/SKILL.md
+++ b/to-issues/SKILL.md
@@ -1,7 +1,7 @@
 # To Issues

-Break a plan or spec into independently-grabbable GitHub issues using
-tracer-bullet vertical slices.
+Break a plan, spec, or PRD into independently-grabbable issues on the project
+issue tracker using tracer-bullet vertical slices.

 ## When to use

@@ -20,5 +20,6 @@
 3. Write each issue: title, background, acceptance criteria, open questions.
 4. Link dependent issues explicitly.
 5. Post all issues in one batch.
+6. Leave a comment on the parent issue listing all child issue URLs.`

const ZOOM_OUT_SKILL_MD = `diff --git a/zoom-out/SKILL.md b/zoom-out/SKILL.md
deleted file mode 100644
--- a/zoom-out/SKILL.md
+++ /dev/null
@@ -1,22 +0,0 @@
-# Zoom Out
-
-Step back from the current task and assess whether it still makes sense
-in the context of the broader goal.
-
-## When to use
-
-When the user seems stuck in implementation details, when the approach has
-drifted from the original plan, or when asked to "zoom out" or "step back".
-
-## Steps
-
-1. Summarise what has been built so far in one paragraph.
-2. Re-read the original brief or goal.
-3. List any divergences between current approach and original intent.
-4. Ask the user: continue, pivot, or restart?
-
-## Notes
-
-- Do not make code changes during a zoom-out pass.
-- This is a diagnostic tool, not an implementation tool.
-- Always end with a concrete question to the user.`

const HANDOFF_SKILL_MD = `diff --git a/handoff/SKILL.md b/handoff/SKILL.md
index 6b3e8d4..a1f9c27 100644
--- a/handoff/SKILL.md
+++ b/handoff/SKILL.md
@@ -1,7 +1,7 @@
 # Handoff

-Compact the current conversation into a handoff document for another agent.
+Compact the current conversation into a structured handoff document for another
+agent or to resume work in a new session.

 ## When to use

@@ -15,5 +15,5 @@
 2. List all open tasks with their current status.
 3. Note any decisions made and why.
 4. Include the exact next action for the receiving agent.
-5. Save the document as HANDOFF.md in the project root.
+5. Save to HANDOFF.md in the project root, or wherever the user specifies.`

// ---------------------------------------------------------------------------
// Skill list (ordered by priority within each state; alpha within group)
// ---------------------------------------------------------------------------

export const SKILLS: Skill[] = [
  // Removed on origin
  {
    id: 'zoom-out',
    label: 'zoom-out',
    state: 'removed',
    files: [
      { filename: 'zoom-out/SKILL.md', shortName: 'SKILL.md', status: 'deleted', rawDiff: ZOOM_OUT_SKILL_MD },
    ],
  },

  // Update available
  {
    id: 'grill-with-docs',
    label: 'grill-with-docs',
    state: 'update',
    files: [
      { filename: 'grill-with-docs/SKILL.md',          shortName: 'SKILL.md',          status: 'modified', rawDiff: GRILL_SKILL_MD },
      { filename: 'grill-with-docs/CONTEXT-FORMAT.md', shortName: 'CONTEXT-FORMAT.md', status: 'modified', rawDiff: GRILL_CONTEXT_FORMAT_MD },
      { filename: 'grill-with-docs/EXAMPLES.md',       shortName: 'EXAMPLES.md',       status: 'added',    rawDiff: GRILL_EXAMPLES_MD },
    ],
  },
  {
    id: 'tdd',
    label: 'tdd',
    state: 'update',
    files: [
      { filename: 'tdd/SKILL.md', shortName: 'SKILL.md', status: 'modified', rawDiff: TDD_SKILL_MD },
    ],
  },
  {
    id: 'to-issues',
    label: 'to-issues',
    state: 'update',
    files: [
      { filename: 'to-issues/SKILL.md', shortName: 'SKILL.md', status: 'modified', rawDiff: TO_ISSUES_SKILL_MD },
    ],
  },

  // Skipped
  {
    id: 'handoff',
    label: 'handoff',
    state: 'skipped',
    files: [
      { filename: 'handoff/SKILL.md', shortName: 'SKILL.md', status: 'modified', rawDiff: HANDOFF_SKILL_MD },
    ],
  },

  // Up-to-date (no diffs)
  { id: 'diagnose',                    label: 'diagnose',                    state: 'uptodate', files: [] },
  { id: 'improve-codebase-architecture', label: 'improve-codebase-architecture', state: 'uptodate', files: [] },
  { id: 'prototype',                   label: 'prototype',                   state: 'uptodate', files: [] },
  { id: 'setup-skills',                label: 'setup-skills',                state: 'uptodate', files: [] },
  { id: 'to-prd',                      label: 'to-prd',                      state: 'uptodate', files: [] },
  { id: 'triage',                      label: 'triage',                      state: 'uptodate', files: [] },
]
