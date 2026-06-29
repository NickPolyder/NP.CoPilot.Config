# Agent & Skill Coordination

> **Intent (anchor):** Define how global, project, and local instructions coordinate with skills, agents, and tools. This file is the single canonical source for precedence, the invocation hierarchy, and handoff rules.
> **Always:** Apply canonical precedence; preserve User → Skill → Agent → Tools; route domain work to the matching custom specialist agent on a task-appropriate model; use structured handoffs for delegated work.
> **Never:** Let an agent invoke an orchestrator skill or let orchestrator skills nest inside each other.
> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored). Project may extend but must not contradict Global. On conflict, the more specific scope wins; within a file, the **Final Rules (Anchor)** win.

## Configuration Precedence

These instructions are global — they load before any repo-level config. The full precedence order:

1. **Global** (`~/.copilot/`) — these files, plus global agents and skills. Always active.
2. **Project** (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`) — repo-specific overrides: framework, infra, build commands, feature toggles.
3. **Local** (gitignored per-user files) — personal overrides that don't belong in source control.

Project config extends global; it should not contradict it. When a project defines specific tooling (e.g., Angular, PostgreSQL, Azure DevOps), agents and skills should respect those choices and skip irrelevant guidance.

## Skill Invocation Hierarchy

Skills and agents follow a strict invocation hierarchy to prevent recursive nesting:

1. **User → Skill** — the user (or another skill's approval gate) invokes a skill.
2. **Skill → Agent** — skills coordinate with specialist agents for domain expertise.
3. **Agent → Tools** — agents use tools (edit, search, run commands) but do **not** invoke orchestrator skills.

Orchestrator skills (`prd-workflow`, `feature-planning`, `git-commit-review`) must never be invoked by an agent or nested inside another orchestrator. If an agent identifies work that would benefit from a skill, it should recommend the skill to the user rather than invoking it directly.

## Agent Routing & Model Fit

When work maps to a domain a specialist agent owns, **prefer dispatching to that custom agent** (e.g. `architect`, `backend-developer`, `qa-engineer`, `security-engineer`) over doing it inline on the orchestrator or using a generic subagent. The orchestrator stays on a strong model and coordinates; each specialist does focused work in its own context window and returns a summary, keeping the orchestrator context lean.

Match the model to the task, not to the role:

- **Judgment work** — architecture review, security/threat analysis, test strategy, design decisions → strong reasoning model (Opus-class).
- **Mechanical work** — scaffolding, extraction, renames, boilerplate, file moves → cheap/fast model (Haiku/mini-class).
- **Orchestrator** — keep on a strong model; push heavy or destructive exploration into subagents so the orchestrator's window stays clean for synthesis.

Set persistent per-agent subagent model defaults with the `/subagents` command. For a one-off, state the model when delegating (e.g. "run the extraction on a Haiku subagent"). Never blanket-cheap judgment agents.

## Agent Handoff Format

When deferring work to another specialist agent, use this structured format:

```
### 🔄 Handoff: {Source Agent} → {Target Agent}

**Reason:** {Why this needs the target's expertise}
**Context:** {Brief background — what was being done, what decision point was reached}
**Request:** {Specific ask — review this design, implement this component, validate this approach}
**Artifacts:** {Relevant files, code snippets, or decisions made so far}
**Constraints:** {Decisions already locked in that the target must respect}
**Priority:** Blocking | Advisory
```

When returning from a handoff:

```
### ✅ Return: {Target Agent} → {Source Agent}

**Request:** {Original ask — one line}
**Outcome:** {What was done / decided / recommended}
**Artifacts:** {Files created/modified, decisions documented}
**Follow-ups:** {Anything the source agent or user should be aware of}
```

## Handoff Rules

- Include enough context for the target to act independently (no conversation history reading).
- **Blocking** = can't proceed without response. **Advisory** = input welcome but non-blocking.
- One handoff per concern — don't bundle unrelated asks.
- Respect locked decisions — don't redesign what another agent already decided.

## Final Rules (Anchor)

1. Apply precedence as Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
2. Follow the invocation hierarchy: User → Skill → Agent → Tools.
3. Use one structured handoff per concern and respect locked decisions.
4. Route domain work to the matching custom specialist agent, on a model that fits the task (judgment → strong, mechanical → cheap).
> If anything above conflicts with these, **these win**.
