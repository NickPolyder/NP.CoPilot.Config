---
name: task-breakdown
description: >
  Breaks a feature design into an ordered, dependency-aware tasks.md — phases,
  complexity estimates, parallelizable markers, and paired test tasks.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are translating an approved design into executable work that can be implemented in dependency order.

Your goals are to:

- **Break down the design** — turn design sections into concrete implementation and test tasks.
- **Sequence work safely** — make dependencies explicit and order tasks within each phase.
- **Expose parallelism** — mark independent tasks so multiple agents can work safely when appropriate.
- **Prepare implementation** — produce `tasks.md` suitable for `implementation-runner`.

---

# When to use this skill

Use this skill whenever:

- A feature design has been approved and needs implementation tasks.
- The user asks for a persisted task breakdown with estimates and dependency ordering.
- A substantial design needs an implementation plan before code changes begin.
- You need the third atomic step in the chain: `codebase-research` → `feature-design-doc` → `task-breakdown` → `implementation-runner`.

Do **not** use this skill for:

- A short in-session checklist for ordinary work; keep that direct.
- Codebase research — use `codebase-research`.
- Writing or revising the feature design — use `feature-design-doc`.
- Executing tasks or editing production code — use `implementation-runner`.
- End-to-end orchestration — recommend `prd-workflow`.

---

# Workflow

Break the design into implementable tasks.

1. **Read the design document** thoroughly.
2. **Generate `docs/features/{feature-name}/tasks.md`** with:

   - **Phases** — group tasks into logical phases (e.g., backend, frontend, integration).
   - **Task format** — each task has: ID, title, description, acceptance criteria, estimated complexity (S/M/L), dependencies.
   - **Ordering** — tasks within a phase are ordered by dependency. Independent tasks are marked as parallelizable.
   - **Test tasks** — every implementation task has a corresponding test task or tests are included in the task itself.

Standalone, return the requested task breakdown and stop; do not prompt for
another phase. When invoked by a coordinator, return the tasks to that owner,
which handles its next approval gate. Task generation does not authorize implementation.

---

# Output locations

Create or update:

- Tasks: `docs/features/{feature-name}/tasks.md`

If the project defines a different docs structure, follow that instead.

The `tasks.md` must include:

- **Phases** — logical groups such as backend, frontend, integration, documentation, or verification.
- **Task format** — ID, title, description, acceptance criteria, estimated complexity (S/M/L), dependencies.
- **Ordering** — dependency-aware order within each phase.
- **Parallelizable markers** — explicit markers for independent tasks.
- **Test tasks** — paired tests for every implementation task, either as separate tasks or included in the task itself.

---

# Coordination

- Use `investigator` only when substantial uncertainty about boundaries,
  sequencing, tests or security needs independent research. Proposed future
  changes belong to bounded `implementer` assignments after approval.
- A requested execution handoff may use `implementation-runner` after this skill ends.

---

# Constraints

- **Tasks only** — do not implement code, create migrations, or change production files as part of task generation.
- **Design is the source of truth** — do not silently change scope; put mismatches or unresolved issues in the task breakdown for approval.
- **Stay bounded** — standalone task generation ends with its deliverable; a coordinator owns any transition approval.
- **Tests travel with work** — every implementation task must include or depend on test work.

---
