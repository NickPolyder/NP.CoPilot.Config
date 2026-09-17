---
name: prd-workflow
description: >
  Orchestrated product workflow that chains codebase research, design document
  generation, task breakdown, and implementation. Each phase requires explicit
  approval before proceeding. Produces design.md, tasks.md, and working code.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

This skill is a **thin orchestrator**. It owns the end-to-end design-first flow and the approval gates between phases, but delegates each phase's detailed procedure to a dedicated atomic skill:

- **`codebase-research`** — read-only investigation producing a grounded research summary.
- **`feature-design-doc`** — `design.md` grounded in that research.
- **`task-breakdown`** — `tasks.md` derived from the design.
- **`implementation-runner`** — code + tests executed in task order.

For single-phase needs, invoke those skills directly. Use this orchestrator when you intend to plan **and** implement a feature end-to-end.

---

# When to use this skill

Use this skill whenever:

- A new feature or project needs end-to-end planning and implementation.
- The user asks to "build", "create", or "develop" something from scratch.
- The user wants a structured design-first workflow rather than ad-hoc coding.

Do **not** use this skill for:

- Quick bug fixes or small tweaks — just code those directly.
- Pure exploration or research — invoke `codebase-research` directly.
- Modifying existing design/task documents — edit them directly.

> **Choosing between `prd-workflow` and `feature-planning`:** Use `prd-workflow` when you intend to **plan AND implement** a feature end-to-end. Use `feature-planning` when you need a **comprehensive plan document only** — no implementation.

> **Boundary:** This workflow sequences only its four phase skills. Return deep test/security needs as recommendations for separate work. Finish this entry workflow's own state before any `git-commit-review`, `test-strategy`, or `security-audit` handoff; a completed phase does not by itself end this workflow or waive another workflow's approval gates.

---

# Workflow

Execute these phases in strict order, delegating each to its atomic skill. **Do not advance to the next phase without user approval.**

## Phase 1: Codebase Research (delegate to `codebase-research`)

Run the `codebase-research` skill to understand structure, patterns, relevant code, and constraints
(including `.github/instructions/project-config.instructions.md` if present). It is read-only.

> **Research complete. Approve moving to design? (yes / no / adjust scope)**

## Phase 2: Design Document (delegate to `feature-design-doc`)

After approval, run the `feature-design-doc` skill to produce `docs/features/{feature-name}/design.md`,
grounded in the Phase 1 research.

> **Design complete. Approve moving to task generation? (yes / no / revise)**

## Phase 3: Task Generation (delegate to `task-breakdown`)

After approval, run the `task-breakdown` skill to produce `docs/features/{feature-name}/tasks.md` from
the design — phases, ordering, dependencies, complexity, and paired test tasks.

> **Tasks generated ({N} tasks across {M} phases). Approve moving to implementation? (yes / no / adjust)**

## Phase 4: Implementation (delegate to `implementation-runner`)

After approval, run the `implementation-runner` skill to execute tasks in order
with tests alongside, updating `tasks.md` and reporting actual per-phase evidence.
It returns to this workflow, not directly into commit review. After applicable
verification, complete this entry workflow's state and offer a separate
`git-commit-review` handoff. Preserve blockers and missing evidence truthfully.

> **Implementation status: {complete / blocked}. Verification: {actual results and limitations}. Ready for separate review? (yes / fix issues first)**

---

# Approval Gate Format

At every gate, present:

```
### Phase {N}: {Name} — Complete

**Summary:** {1-2 sentence summary}
**Artifacts:** {files created/modified}
**Risks/Notes:** {anything the user should know}

Approve moving to {next phase}? (yes / no / adjust)
```

---

# Coordination

- **`codebase-research` / `feature-design-doc` / `task-breakdown` / `implementation-runner`** — the four phase skills this orchestrator sequences.
- Delegate substantial unresolved research/design questions to `investigator`
  and approved bounded changes to `implementer`; supply only needed domain notes.
- Keep small phase work inline. Recommend separate `test-strategy` or
  `security-audit` work when deeper planning is needed, without nesting workflows.
- **Documentation skill** — after implementation, recommend `documentation` to update `docs/`.
- **Git commit review skill** — recommend a separate `git-commit-review` only
  after this entry workflow completes; do not embed commit gates here.

---

# Constraints

- **Keep the phases atomic** — delegate each phase's detail to its dedicated skill; do not inline the full procedures here.
- **Separate delivery** — finish the verified entry workflow before a separate
  `git-commit-review`; never let a phase start it while this parent is active.
- **Use dedicated depth skills** — reference `test-strategy` and `security-audit` when deep test or security artifacts are needed.

---

# Output locations

All artifacts go under the project's docs directory:

- Design: `docs/features/{feature-name}/design.md`
- Tasks: `docs/features/{feature-name}/tasks.md`
- Code: appropriate source directories per project conventions.

If the project defines a different docs structure, follow that instead.

---
