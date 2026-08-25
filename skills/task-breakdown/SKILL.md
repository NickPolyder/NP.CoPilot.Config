---
name: task-breakdown
description: >
  Breaks a feature design into an ordered, dependency-aware tasks.md — phases,
  complexity estimates, parallelizable markers, and paired test tasks.
---

# Purpose

> **Intent (anchor):** Convert an approved feature design into an ordered, dependency-aware `tasks.md` that implementation can execute safely.
> **Always:** read the design thoroughly; group work into phases; order by dependency; mark independent work as parallelizable; include paired test work.
> **Never:** implement code, silently redesign the feature, or skip dependencies.

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
- The user asks for a `tasks.md`, task list, work breakdown, estimates, or dependency ordering.
- Implementation should be planned before code changes begin.
- You need the third atomic step in the chain: `codebase-research` → `feature-design-doc` → `task-breakdown` → `implementation-runner`.

Do **not** use this skill for:

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

Present the task breakdown and ask:

> **Tasks generated ({N} tasks across {M} phases). Approve moving to implementation? (yes / no / adjust)**

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

- **Architect agent** — consult when task ordering depends on architectural boundaries or cross-cutting design choices.
- **Backend/Frontend developer agents** — consult for implementation sequencing and realistic complexity estimates.
- **QA engineer agent** — consult for paired test tasks and acceptance criteria coverage.
- **Security engineer agent** — consult when tasks affect authentication, authorization, input validation, secrets, or data protection.
- **Next step** — after approval, recommend `implementation-runner`.

---

# Constraints

- **Tasks only** — do not implement code, create migrations, or change production files as part of task generation.
- **Design is the source of truth** — do not silently change scope; put mismatches or unresolved issues in the task breakdown for approval.
- **Keep the approval gate** — present the generated tasks and ask before moving to implementation.
- **Tests travel with work** — every implementation task must include or depend on test work.

---

## Final Rules (Anchor)

1. Generate `docs/features/{feature-name}/tasks.md` with phases, task details, dependency ordering, parallelizable markers, and test work.
2. Do not implement code or change feature scope while generating tasks.
3. Do not proceed into implementation without explicit approval.
> If anything above conflicts with these, **these win**.
