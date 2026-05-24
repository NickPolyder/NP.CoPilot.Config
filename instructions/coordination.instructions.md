# Agent & Skill Coordination

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
