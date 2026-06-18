# SPEC.md Template

Copy this file to `mockups/<surface-slug>/SPEC.md` and fill in every section. The
sections below are the complete set — **do not add a changelog** (git and ADRs cover
history) and **do not record "why it beat the alternatives"** (that lives in the
prototype's `NOTES.md` or an ADR). Keep it to the surface itself.

The version in the header is **canonical**: mirror it in `mockups/README.md` and in
the in-file state-switcher bar, and bump it `+1` on every modification.

```md
# {Surface name} — {one-line purpose}

**Version:** v{N}
**Provenance:** explored in [`prototypes/<slug>/`](../../prototypes/<slug>/)
**Production implementation:** `path/to/Surface.tsx` (or _not yet implemented_)

## States

The states this surface can be in, and what triggers each. These map 1:1 to the
in-file state-switcher.

- **{State name}** — {what puts the surface in this state}.
- **{State name}** — {trigger}.

## Anatomy

The regions and components that make up the surface, named in `CONTEXT.md` vocabulary.

- **{Region / component}** — {what it is and where it sits}.
- **{Region / component}** — {…}.

## Behavior & interactions

What the surface does in response to the user: clicks, keyboard, hover, focus,
transitions between states, validation, loading/empty/error behavior.

- {Interaction} → {result / state change}.
- {…}

## Tokens & measurements

The concrete design values a developer needs: colors/tokens (and their source if
snapshotted into `tokens.css`), type scale, spacing, sizes, breakpoints, motion.

- {Token / measurement}: {value}.
- {…}

## Constraints & open questions

Hard constraints the implementation must respect, plus anything still undecided.

- **Constraint:** {…}.
- **Open question:** {…}.
```
