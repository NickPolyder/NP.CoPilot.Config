---
name: codebase-research
description: >
  Investigates an existing codebase to produce a grounded research summary —
  structure, patterns, conventions, relevant code, and constraints — before
  any design work. Read-only.
---

# Purpose

> **Intent (anchor):** Produce a read-only, grounded research summary of an existing codebase before any design work starts.
> **Always:** discover structure first; identify existing patterns and relevant code; read project configuration; capture constraints and reusable abstractions.
> **Never:** edit files, design the feature, or generate implementation tasks.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are investigating what already exists so later design work is grounded in the actual project rather than assumptions.

Your goals are to:

- **Map the codebase** — understand directory layout, key configuration, and entry points.
- **Identify patterns** — capture frameworks, architecture style, naming conventions, and test approach.
- **Find relevant code** — locate modules, services, components, or tests connected to the requested feature area.
- **Document constraints** — note dependencies, tech debt, abstractions, and project-specific instructions that later phases must respect.

---

# When to use this skill

Use this skill whenever:

- A feature idea needs research before design decisions are made.
- The user asks to investigate, explore, summarize, or understand a codebase area.
- A later `feature-design-doc` should be grounded in real project structure, patterns, and constraints.
- You need the first atomic step in the chain: `codebase-research` → `feature-design-doc` → `task-breakdown` → `implementation-runner`.

Do **not** use this skill for:

- Design work — use `feature-design-doc`.
- Task generation — use `task-breakdown`.
- Implementation — use `implementation-runner`.
- End-to-end gated planning and implementation — recommend `prd-workflow` instead of nesting it.

---

# Workflow

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

# Output Format

Produce a concise research summary in the conversation unless the user explicitly asks for a file.

Include:

- **Project structure** — directory layout, key configuration files, entry points.
- **Existing patterns** — frameworks, architecture, naming conventions, and test approach.
- **Relevant code** — modules, services, components, tests, and extension points related to the feature area.
- **Constraints** — dependencies, tech debt, abstractions to reuse, project instructions, and known risks.
- **Next step** — recommend `feature-design-doc` when the research is approved.

No files should be edited or created by this skill.

---

# Coordination

- **Architect agent** — consult for interpreting architectural patterns and boundaries.
- **Backend/Frontend developer agents** — consult for domain-specific code paths and framework conventions.
- **QA engineer agent** — consult for existing test strategy and test coverage signals.
- **Security engineer agent** — consult when existing authentication, authorization, or input validation constraints affect the feature area.
- **Next step** — after approval, recommend `feature-design-doc`.

---

# Constraints

- **Read-only only** — do not create, edit, move, or delete files.
- **No design decisions yet** — document what exists and what constrains the work; leave solution design to `feature-design-doc`.
- **Keep the approval gate** — present the research summary and ask before moving to design.
- **Respect configuration precedence** — project and local instructions may refine global conventions but must not contradict them.

---

## Final Rules (Anchor)

1. This skill is read-only; never edit or create files.
2. The output must cover structure, patterns, relevant code, constraints, and project configuration.
3. Do not proceed into design; recommend `feature-design-doc` only after approval.
> If anything above conflicts with these, **these win**.
