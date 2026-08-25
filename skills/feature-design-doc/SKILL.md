---
name: feature-design-doc
description: >
  Generates a feature design document (design.md) grounded in prior codebase
  research — overview, goals, user stories, scope, data model, API, UI, and
  test/security planning summaries.
---

# Purpose

> **Intent (anchor):** Generate a feature `design.md` that a developer, including a junior developer, could implement from.
> **Always:** ground the design in prior codebase research; ask 2-3 informed clarifying questions; include every required design section; gate before task generation.
> **Never:** invent patterns that contradict the codebase, generate implementation tasks, or write production code.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are producing a design document that translates approved research and feature intent into a clear implementation blueprint.

Your goals are to:

- **Clarify scope** — ask only the key questions needed to resolve ambiguity.
- **Document the design** — create `design.md` with the required sections and enough detail to implement.
- **Ground decisions** — align with existing codebase patterns, abstractions, constraints, and project instructions.
- **Prepare handoff** — make the next atomic step, `task-breakdown`, straightforward.

---

# When to use this skill

Use this skill whenever:

- Codebase research is complete and the user approves moving to design.
- A feature needs a standalone `docs/features/{feature-name}/design.md`.
- The user asks for a feature design document grounded in an existing repository.
- You need the second atomic step in the chain: `codebase-research` → `feature-design-doc` → `task-breakdown` → `implementation-runner`.

Do **not** use this skill for:

- Initial codebase investigation — use `codebase-research`.
- Generating implementation tasks — use `task-breakdown`.
- Executing code changes — use `implementation-runner`.
- Comprehensive plan-only orchestration — recommend `feature-planning` instead of nesting it.

---

# Workflow

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
   - **Test Strategy** — planning summary of what to test at each pyramid level; recommend `test-strategy` for dedicated depth.
   - **Security Considerations** — planning summary of authentication, authorization, and input validation; recommend `security-audit` for STRIDE/OWASP depth.
   - **Open Questions** — anything unresolved.

Present the design and ask:

> **Design complete. Approve moving to task generation? (yes / no / revise)**

---

# Output locations

Create or update:

- Design: `docs/features/{feature-name}/design.md`

If the project defines a different docs structure, follow that instead.

The design must include:

- **Overview**
- **Goals**
- **User Stories**
- **Scope**
- **Data Model**
- **API Design**
- **UI Design**
- **Test Strategy**
- **Security Considerations**
- **Open Questions**

---

# Coordination

- **Architect agent** — consult for architectural decisions during design.
- **Backend/Frontend developer agents** — consult for API, data model, UI, and implementation feasibility questions.
- **QA engineer agent** — consult for planning-level test strategy decisions; recommend `test-strategy` when depth is needed.
- **Security engineer agent** — consult for planning-level security considerations; recommend `security-audit` when depth is needed.
- **Next step** — after approval, recommend `task-breakdown`.

---

# Constraints

- **Design only** — do not generate `tasks.md`, implement code, or define commit strategy.
- **Research-grounded** — if research is missing or insufficient, ask for it or recommend `codebase-research` before writing the design.
- **Keep the approval gate** — present the design and ask before moving to task generation.
- **Use dedicated depth skills** — reference `test-strategy` and `security-audit` when deep test or security artifacts are needed.

---

## Final Rules (Anchor)

1. Generate `docs/features/{feature-name}/design.md` with every required section.
2. Ground the design in prior research and project conventions; do not invent contradictory patterns.
3. Do not proceed into task generation without explicit approval.
> If anything above conflicts with these, **these win**.
