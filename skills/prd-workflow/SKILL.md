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

You are running a structured product development workflow — from understanding through implementation.

Your goals are to:

- **Research the codebase** before making any design decisions.
- **Produce a design document** (`design.md`) grounded in what actually exists.
- **Break the design into executable tasks** (`tasks.md`) with clear ordering and dependencies.
- **Implement the tasks** in order, with tests alongside code.
- **Gate every phase transition** — never proceed without explicit user approval.

---

# When to use this skill

Use this skill whenever:

- A new feature or project needs end-to-end planning and implementation.
- The user asks to "build", "create", or "develop" something from scratch.
- The user wants a structured design-first workflow rather than ad-hoc coding.

Do **not** use this skill for:

- Quick bug fixes or small tweaks — just code those directly.
- Pure exploration or research — use investigation tools instead.
- Modifying existing design/task documents — edit them directly.

---

# Workflow

Execute these phases in strict order. **Do not advance to the next phase without user approval.**

## Phase 1: Codebase Research

Before designing anything, understand what exists.

1. **Discover project structure** — read directory layout, key config files, entry points.
2. **Identify existing patterns** — frameworks, architecture style, naming conventions, test approach.
3. **Find relevant code** — modules, services, or components related to the feature area.
4. **Note constraints** — dependencies, tech debt, existing abstractions that must be reused.
5. **Check project config** — if `.github/instructions/project-config.instructions.md` exists, read it for framework, infra, and tooling choices.

**Output:** Brief research summary (what exists, what's relevant, what constrains us).

Present the summary and ask:

> **Research complete. Approve moving to design? (yes / no / adjust scope)**

---

## Phase 2: Design Document

Produce a design document that a developer (including a junior) could implement from.

1. **Ask 2-3 clarifying questions** — scope, constraints, preferences. Keep questions informed by the research.
2. **Generate `docs/features/{feature-name}/design.md`** with these sections:

   - **Overview** — what and why, in 2-3 sentences.
   - **Goals** — measurable outcomes.
   - **User Stories** — as a [role], I want [action], so that [value]. Include acceptance criteria.
   - **Scope** — what's in, what's explicitly out.
   - **Data Model** — entities, relationships, migrations needed.
   - **API Design** — endpoints, request/response shapes, status codes.
   - **UI Design** — components, layouts, user flows (if applicable).
   - **Test Strategy** — what to test at each pyramid level.
   - **Security Considerations** — authentication, authorization, input validation.
   - **Open Questions** — anything unresolved.

Present the design and ask:

> **Design complete. Approve moving to task generation? (yes / no / revise)**

---

## Phase 3: Task Generation

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

## Phase 4: Implementation

Execute tasks in order, producing working code with tests.

1. **Follow task order** — respect dependencies. Do not skip ahead.
2. **For each task:**
   - Implement the code change.
   - Write unit tests alongside the code.
   - Mark the task as complete in `tasks.md` (prefix with `[x]`).
3. **After each phase** (group of related tasks), report:
   - What was implemented.
   - Test results (pass/fail counts).
   - Any deviations from the design.
4. **After all tasks are complete**, run the full test suite and report results.

After implementation, ask:

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

- **Architect agent** — consult for architectural decisions during design.
- **Backend/Frontend developer agents** — consult during implementation for pattern questions.
- **QA engineer agent** — consult for test strategy decisions.
- **Security engineer agent** — consult for security considerations in design.

---

# Output locations

All artifacts go under the project's docs directory:

- Design: `docs/features/{feature-name}/design.md`
- Tasks: `docs/features/{feature-name}/tasks.md`
- Code: appropriate source directories per project conventions.

If the project defines a different docs structure, follow that instead.
