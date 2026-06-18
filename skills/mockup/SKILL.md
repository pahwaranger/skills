---
name: mockup
description: Create and maintain a living mockup — the single locked design for a UI surface that developers replicate in the production app, the repo's equivalent of a Figma frame. Runs the `prototype` skill to explore variants, promotes the winner to a self-contained, versioned mockup under `mockups/`, and keeps it as the authoritative reference (design changes land here first; production follows). Use when the user wants to create or update a mockup, lock in a design, or produce a design reference for developers to build from — e.g. "make a mockup", "mock up this screen", "lock the design for X", "update the mockup".
---

# Mockup

A **mockup** is the single locked design for one UI surface — the authoritative reference a developer replicates in the production app, the repo's equivalent of a locked Figma frame. It is _living_: as the design evolves, the change lands in the mockup first and production follows. Each mockup is self-contained and severable, lives under `mockups/<surface-slug>/`, and carries a plain-integer version that ADRs, PRDs, and tickets cite when they specify UI work.

This skill **promotes the winning [`prototype`](../prototype/SKILL.md) variant into a mockup and keeps it current**. The prototype is the throwaway exploration; the mockup is the locked answer. (See the **Design references** section of [`CONTEXT.md`](../../CONTEXT.md) for the canonical definitions of Prototype and Mockup — this skill uses that vocabulary throughout.)

## Trigger split — explore vs. lock

Pick the skill by what the user wants, not by the word they used:

- **Explore** — "what should this look like?", "try a few designs", "let me play with it" → [`prototype`](../prototype/SKILL.md). Several competing variants, switchable, thrown away once the question is answered.
- **Lock a durable reference** — "make a mockup", "lock the design for X", "this is the design developers should build from", "update the mockup" → **this skill**. One locked design, kept current, cited by version.

"Mock up this screen" is ambiguous: if the design is still open, run `prototype` first to explore, then come back here to lock the winner. If the design is already settled, go straight to Create mode below.

## Mode auto-detection

Check whether `mockups/<surface-slug>/` already exists for the surface in question:

- **It does not exist** → **Create mode**. Run the full prototype → promote → flatten → write → register flow.
- **It exists** → **Update mode**. Edit the existing mockup in place and bump the version.

Update is a lighter Create, not a separate branch — the same invariants (self-contained, state-switcher, fidelity rules, no production dependency) apply to both.

## Surface unit & states

**One UI surface per mockup.** A surface is a coherent screen, tab, panel, or flow step — the thing a developer would sit down to build in one go (e.g. the review tab, the settings screen, the empty state of the inbox).

A real surface has **states** — loading, empty, populated, error, an expanded row, a confirmation dialog, etc. The mockup captures _all_ of them. Every state is reachable through a **floating state-switcher**:

- A small, fixed-position bar (bottom-centre), **visually distinct** from the surface — high-contrast pill, subtle shadow — so a reader never mistakes it for part of the design.
- It is **scaffolding, not part of the surface.** It mirrors the `prototype` variant bar, but it switches **states of the one locked design**, not competing designs.
- It lists the surface's states by name (matching the **States** section of `SPEC.md`), cycles with left/right arrows and `←`/`→` keys (don't intercept arrow keys while an `<input>`, `<textarea>`, or `[contenteditable]` is focused), and reflects the current state in a URL param (e.g. `?state=empty`) so a shared link reopens the same state.
- It also shows the current **version** (e.g. `review-tab · v3`) so anyone looking at the file knows which version they're seeing.

If the surface has exactly one state, a switcher is still worth including (it documents that there is only one) but may be a single static label.

## Fidelity

A mockup must look right enough that a developer can build production from it without guessing. It is **always fully self-contained** — no build step, no framework, no `package.json`, no serve script. Open `index.html` in a browser and it just works.

How the styling is sourced depends on the target:

- **Web target with a token system** (CSS custom properties, a Tailwind theme, a design-token file, etc.) → **snapshot** the relevant tokens into a co-located `tokens.css`. **Copy them in — never import from production**, and note the source at the top of `tokens.css` (e.g. `/* Snapshot of src/styles/tokens.css @ <commit/date> — copy, do not import */`). The snapshot is what keeps the mockup severable.
- **Non-web target** (native mobile, desktop, TUI, etc.) or a web target with no token system → **hand-craft platform-approximate CSS** that reads as that platform (system fonts, native control metrics, platform spacing). The goal is recognisable fidelity, not pixel perfection.

Either way the result is one `index.html` with inline or co-located CSS and vanilla JS only as needed (the state-switcher is the usual reason for any JS at all).

## No-production-dependency invariant

**Production never imports from `mockups/`, and a mockup never imports from production.** A mockup is severable: you could delete the entire `mockups/` tree and production would still build. This is why tokens are _copied_ into `tokens.css` rather than referenced. The mockup is the reference a developer reads and replicates by hand — not a module anything links against.

## Slugs

- **kebab-case, naming the surface** — `review-tab`, `settings-screen`, `inbox-empty-state`. Name the surface, not the feature or the ticket.
- The mockup lives at `mockups/<surface-slug>/`.
- `SPEC.md` **back-links to the originating** `prototypes/<slug>/` so a reader can trace the mockup to the exploration it came from. The prototype slug and the mockup slug are often the same word — that's fine.

## Versioning

- **Plain integers**, written `vN`. **`v1` on create; +1 on every modification.**
- The version is **canonical in the `SPEC.md` header**, **mirrored in `mockups/README.md`**, and **shown in the in-file state-switcher bar**. Keep all three in sync whenever you bump.
- **Only the current version is recorded.** There is no `v1/`, `v2/` history in the tree — git holds history, and the `SPEC.md` has no changelog. Drift between the mockup and production is _not_ tracked inside the mockup; it is signalled by an **open catch-up ticket** (see the offers below).
- **Citation form:** anything specifying UI work references `mockups/<slug>` (vN) — e.g. "implement per `mockups/review-tab` (v3)".

## Create mode

The surface has no mockup yet. Produce one from a prototype.

1. **Explore with `prototype` (UI flow).** Run the [`prototype`](../prototype/SKILL.md) UI flow to generate several radically different variants of the surface and let the user pick a winner. If a suitable prototype already exists for this surface, reuse it rather than re-exploring. When `prototype` is invoked _by_ this skill, the **winning variant is handed back here for promotion** — that is the promotion handoff.
2. **Promote the winning variant.** Take the chosen variant as the starting point for the mockup. Do not promote competing variants; the losers stay in `prototypes/<slug>/` as the record of how the decision was reached.
3. **Flatten to a self-contained `index.html`.** Strip the variant out of the framework and the prototype's switcher harness. Produce a single no-build `index.html` under `mockups/<surface-slug>/`: inline or co-located CSS, vanilla JS only as needed, **no framework, no `package.json`, no serve script.** Apply the fidelity rule — snapshot tokens into `tokens.css` for a web token-system, otherwise hand-craft platform-approximate CSS.
4. **Add the floating state-switcher.** Wire every state of the surface to the switcher described above, showing the slug and `v1`.
5. **Write `SPEC.md` from the template.** Copy [`SPEC-TEMPLATE.md`](SPEC-TEMPLATE.md) to `mockups/<surface-slug>/SPEC.md` and fill in every section. Set the version to **`v1`**, back-link the provenance to `prototypes/<slug>/`, and leave the production-implementation pointer as "not yet implemented" until the catch-up/implementation ticket lands it.
6. **Register it.** Add a row to `mockups/README.md` (create the file with the table header if it's the first mockup — see the registry shape below).

Then run the three offers.

## Update mode

The surface already has a mockup. Evolve it in place — design changes land here first.

1. **Edit `index.html` and `SPEC.md` directly.** No new directory, no versioned copy. Apply the same fidelity, self-contained, and state-switcher rules; if you re-snapshot tokens, update the source note in `tokens.css`.
2. **Increment the version.** Bump `vN` → `vN+1` in all three places: the `SPEC.md` header, the `mockups/README.md` row, and the in-file switcher bar.
3. **Offer a production catch-up ticket.** Production now trails the mockup. Offer to file a catch-up ticket via [`to-tickets`](../to-tickets/SKILL.md) so the drift is tracked (this is the mechanism that records drift — the mockup itself stays single-version). This is the update-mode form of the third offer below.

Then run the remaining offers as applicable.

## The three offers at lock / update

These run when a mockup is created or updated. **They are offers, never automatic** — surface them to the user and let them decide. Each delegates to an existing skill; don't reimplement it here.

1. **New anatomy nouns → `CONTEXT.md` glossary.** If the mockup introduces durable names for regions or components that the team will use in conversation (a "review rail", a "state-switcher", a "summary card"), **offer** to add them to the **Design references** / relevant section of [`CONTEXT.md`](../../CONTEXT.md) via [`grill-with-docs`](../grill-with-docs/SKILL.md). Glossary, not spec — keep definitions tight.
2. **An ADR — only if it clears the bar.** Offer an ADR **only** when a design decision is **hard to reverse**, **surprising without context**, and **the result of a real trade-off** (the three-part test in [`grill-with-docs`](../grill-with-docs/SKILL.md) / `ADR-FORMAT.md`). Most mockups need no ADR; skip it unless all three hold.
3. **A ticket via `to-tickets`.** On **create**, offer an **implementation ticket** to build the surface in production from the new mockup. On **update**, offer a **catch-up ticket** so production follows the new version. Either way, delegate to [`to-tickets`](../to-tickets/SKILL.md) and cite the mockup by version — `mockups/<slug>` (vN).

## `mockups/` layout

```
mockups/
├── README.md                     ← registry (table; see below)
└── <surface-slug>/
    ├── index.html                ← self-contained, no-build; includes the state-switcher
    ├── SPEC.md                   ← from SPEC-TEMPLATE.md; version is canonical here
    └── tokens.css                ← only when snapshotting a web token system
```

### `mockups/README.md` registry shape

A single table, one row per mockup:

```md
# Mockups

Living design references. Each row is the authoritative design for one UI surface;
production replicates it. Cite a mockup by version when specifying UI work, e.g.
`mockups/review-tab` (v3).

| Surface | Mockup | Version | Production implementation |
| --- | --- | --- | --- |
| Review tab | [mockups/review-tab/](review-tab/) | v3 | `src/app/review/ReviewTab.tsx` |
| Settings screen | [mockups/settings-screen/](settings-screen/) | v1 | _not yet implemented_ |
```

Keep the **Version** column in sync with each `SPEC.md` header. The **Production implementation** column points at the production path once it exists, or reads _not yet implemented_ until the implementation ticket lands.

## Scope

This skill authors and maintains mockups. It does **not** build production code (that's the implementation/catch-up ticket's job) and it does **not** delete prototypes (they stay under `prototypes/` as the record of the exploration).
