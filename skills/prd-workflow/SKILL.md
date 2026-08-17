---
name: prd-workflow
description: >
  Orchestrated product workflow that chains codebase research, design document
  generation, task breakdown, and implementation. Each phase requires explicit
  approval before proceeding. Produces design.md, tasks.md, and working code.
tags:
  - planning
  - design
  - tasks
  - implementation
  - workflow
  - orchestration
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles, todo]
---

# Purpose

> **Intent (anchor):** Drive a gated, design-first product workflow for one approved feature by sequencing the atomic `codebase-research`, `feature-design-doc`, `task-breakdown`, and `implementation-runner` skills through explicit approval gates.
> **Always:** research before design; produce `design.md` and `tasks.md`; require explicit approval before every phase transition.
> **Never:** skip approval gates.

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

> **Boundary:** This workflow sequences only its four phase skills. For deep test/security work, recommend `test-strategy` or `security-audit`; for commit review and commit creation, delegate to `git-commit-review` after this workflow's implementation is verified.

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

After approval, run the `implementation-runner` skill to execute tasks in order with tests alongside,
updating `tasks.md` and reporting per-phase results. After implementation is verified, hand off commit
review and commit creation to `git-commit-review`.

> **Implementation complete. {passed}/{total} tests passing. Ready for review? (yes / fix issues first)**

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
- **Architect agent** — consult for architectural decisions during design.
- **Backend/Frontend developer agents** — consult during implementation for pattern questions.
- **QA engineer agent** — consult for planning-level test strategy; recommend `test-strategy` when depth is needed.
- **Security engineer agent** — consult for planning-level security; recommend `security-audit` when depth is needed.
- **Documentation skill** — after implementation, recommend `documentation` to update `docs/`.
- **Git commit review skill** — after implementation is verified, delegate commits to `git-commit-review` instead of embedding commit workflow here.

---

# Constraints

- **Keep the phases atomic** — delegate each phase's detail to its dedicated skill; do not inline the full procedures here.
- **Delegate commits** — use `git-commit-review` for commit review and commit creation after implementation is verified.
- **Use dedicated depth skills** — reference `test-strategy` and `security-audit` when deep test or security artifacts are needed.

---

# Output locations

All artifacts go under the project's docs directory:

- Design: `docs/features/{feature-name}/design.md`
- Tasks: `docs/features/{feature-name}/tasks.md`
- Code: appropriate source directories per project conventions.

If the project defines a different docs structure, follow that instead.

---

## Final Rules (Anchor)

1. Keep this workflow to its four defined phases; recommend other dedicated workflows after it completes.
2. Execute phases in strict order via their atomic skills. Do not advance to the next phase without user approval.
3. Keep this orchestrator thin — delegate each phase's detail to its dedicated skill and commits to `git-commit-review`.
> If anything above conflicts with these, **these win**.
