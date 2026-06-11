# {{REPO_NAME}} — Plan

> The **canonical design + architecture** for this repo. This is the source of
> truth an agent reads before doing work. Keep it current: when an implementation
> decision diverges from this doc, update the doc (and record *why* in an ADR).

## Problem

{{WHAT_PROBLEM_THIS_REPO_SOLVES — the recurring pain, who feels it, why it
matters. 1–3 short paragraphs.}}

## Decision

{{THE_HIGH_LEVEL_APPROACH_CHOSEN — one or two paragraphs. Link the ADRs that
back the big choices, e.g. "See docs/decisions/0001-….md".}}

## Approach

{{HOW_IT_WORKS_AT_A_HIGH_LEVEL — the major components and how they fit together.
Use sub-sections per component.}}

### {{COMPONENT_1}}

{{Description, responsibilities, key constraints.}}

### {{COMPONENT_2}}

{{Description, responsibilities, key constraints.}}

## Architecture / layout

```
{{REPO_DIRECTORY_MAP — annotate the important folders and what lives where.}}
```

## Key constraints

> The invariants the design depends on. Cross-reference Hard Rules in
> `.github/copilot-instructions.md`.

- {{CONSTRAINT_1}}
- {{CONSTRAINT_2}}

## Open questions

- {{OPEN_QUESTION_1}}
- {{OPEN_QUESTION_2}}

## Out of scope

- {{OUT_OF_SCOPE_1}}
- {{OUT_OF_SCOPE_2}}

## References

- [`docs/TASKS.md`](TASKS.md) — phased delivery plan
- [`docs/decisions/`](decisions/) — architecture decision records
