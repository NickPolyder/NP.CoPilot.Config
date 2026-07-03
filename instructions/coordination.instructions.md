# Agent & Skill Coordination

> **Intent (anchor):** Define how global, project, and local instructions coordinate with skills, agents, and tools. This file is the single canonical source for precedence, the invocation hierarchy, and handoff rules.
> **Always:** Apply canonical precedence; preserve User → Skill → Agent → Tools; take direct action on small tasks and delegate only substantial, specialized, or parallelizable work to the matching specialist on a task-appropriate model; use structured handoffs.
> **Never:** Let an agent invoke an orchestrator skill, let orchestrator skills nest, delegate reflexively on a domain keyword, or delegate beyond the depth cap (orchestrator → specialist → at most one sideways handoff → terminal).
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

**Direct action first.** For anything you can finish in a few tool calls — reading files, small edits, simple lookups, answering from context — just do it. Delegation is for **substantial, specialized, or parallelizable** work, not a reflex triggered by a domain keyword.

When work is substantial *and* maps to a domain a specialist owns, dispatch to that custom agent (e.g. `architect`, `backend-developer`, `qa-engineer`, `security-engineer`) rather than doing heavy specialist work inline on the orchestrator. The orchestrator stays on a strong model and coordinates; each specialist does focused work in its own context window and returns a summary, keeping the orchestrator context lean.

Match the model to the task, not to the role:

- **Judgment work** — architecture review, security/threat analysis, test strategy, design decisions → strong reasoning model (Opus-class).
- **Mechanical work** — scaffolding, extraction, renames, boilerplate, file moves → cheap/fast model (Haiku/mini-class).
- **Orchestrator** — keep on a strong model; push heavy or destructive exploration into subagents so the orchestrator's window stays clean for synthesis.

Set persistent per-agent subagent model defaults with the `/subagents` command. For a one-off, state the model when delegating (e.g. "run the extraction on a Haiku subagent"). Never blanket-cheap judgment agents.

## Specialist Agent Delegation

Substantial domain work belongs to the specialist that owns it. As orchestrator, you **coordinate and synthesize** — for work that is large, specialized, or parallelizable, dispatch to the owning agent, let it work in its own context window, and integrate the result. Small, mechanical, or read-only tasks stay inline (see **Delegation Discipline & Loop Prevention** below). This keeps the orchestrator's window lean and the output expert-quality.

**Delegate by domain:**

| When the task involves… | Delegate to |
|---|---|
| Architecture decisions, layer boundaries, dependency direction, patterns, SOLID/DDD trade-offs | `architect` |
| .NET backend — Web API, EF Core, DDD, CQRS, messaging | `backend-developer` |
| Angular / front-end Blazor — components, accessibility, responsive UI | `frontend-developer` |
| End-to-end features spanning .NET backend **and** Angular/Blazor frontend | `fullstack-developer` |
| Node.js / TypeScript / Next.js dashboards and small web apps | `node-developer` |
| Python — MCP servers, FastAPI, async services, automation | `python-developer` |
| Data modeling, migrations, query optimization, data integrity | `database-engineer` |
| Azure Service Fabric — Reliable Services/Actors, clusters, upgrades, partitioning | `service-fabric-engineer` |
| Service integration, API contracts, messaging, resilience, observability, distributed design | `systems-engineer` |
| CI/CD, IaC, containers, cloud infra, monitoring, automation scripting | `devops-engineer` |
| Security — threat modeling, vulnerability analysis, authn/authz, secure coding | `security-engineer` |
| Test strategy, coverage analysis, pyramid balance, edge-case discovery | `qa-engineer` |
| Deterministic unit tests, test plans, mutation/branch/condition coverage | `test-engineer` |
| Code review — bugs, logic errors, security, pattern violations | `code-reviewer` |
| Requirements → user stories, acceptance criteria, backlog shaping | `product-owner` |
| UX — research, wireframes, prototypes, usability, design systems, IA | `ux-engineer` |

**Multi-domain work:** chain the specialists rather than absorbing their work. A typical feature flows `product-owner` → `architect` → the relevant developer agent → `test-engineer` → `qa-engineer` → `security-engineer` → `code-reviewer`. Use `fullstack-developer` when a change genuinely spans both tiers; otherwise split across `frontend-developer` and `backend-developer`.

**Stays on the orchestrator (do it inline):** single-file lookups, reading files, mechanical edits, answering questions from context, Trivial-tier changes, and the coordination/synthesis of specialist output. When unsure whether a task is big enough to delegate, **default to doing it inline** unless it is genuinely substantial, needs specialized judgment, or is parallelizable — reflexive over-delegation (and the loops it causes) is the more common failure than under-delegation.

## Delegation Discipline & Loop Prevention

Delegation must terminate. The depth cap and tier gate below exist specifically to stop the "see a domain word → delegate → the sub-agent re-reads the same mandate → re-delegates → loop" failure.

**Delegation depth cap (hard):**

- **Depth 0 → 1:** the orchestrator delegates a substantial task to a specialist. Normal.
- **Depth 1 → 2:** a specialist that genuinely hits *another* domain may make **at most ONE** sideways handoff to that specialist.
- **Depth 2 is terminal:** an agent that received work via a sideways handoff **completes it with tools and never delegates again**.
- **Never** hand off to an agent already in the current chain, and **never** exceed one sideways handoff. Additional domain needs are surfaced as *recommendations in the return summary* for the orchestrator to route on a later turn.

**A delegated agent is the doer.** Once you receive delegated work, your job is to *do it with tools* — not to route it onward. The "Defer to / Consult" lists in agent definitions are **advisory**: they tell you whose input to surface as a recommendation, not a trigger to spawn another agent.

**Tier gate (from the Development Workflow):**

| Tier | Delegation posture |
|------|--------------------|
| **Trivial** | Never delegate. Do it inline. |
| **Standard** | Inline by default. Delegate only for genuinely specialized judgment or substantial multi-step work. |
| **Full** | Coordinate/delegate across specialists as designed. |

This reconciles with the CLI's built-in guidance: **direct action first** — any task completable in a few tool calls is done inline; delegation is reserved for substantial, specialized, or parallelizable work.

## Test Work Delegation

Substantial unit-test authoring is owned by the `test-engineer` agent. As orchestrator, coordinate it for Standard/Full-tier test work — hand off rather than producing large test suites, plans, or reviews inline. Trivial, inline, or single-assertion test tweaks that travel with a small change may stay inline.

- **Delegate to `test-engineer`** whenever the user asks to: write tests, write a test plan, verify/review tests, improve coverage, or interpret CI test feedback.
- **After code changes** (new file, modified file, refactor, feature, or bug fix) in the **Standard** or **Full** tier, delegate to `test-engineer` — hand off the changed code and request an updated test plan plus updated unit tests, so tests travel with the code. *(Trivial-tier changes and pure docs/config changes are exempt.)*
- **Broader test scope stays with the strategist.** Route test *strategy* across the pyramid (integration/E2E/performance, risk-based planning) to `qa-engineer`; route durable strategy or retrospective gap-filling to the `test-strategy` / `test-gap-*` skills. `test-engineer` owns concrete deterministic unit tests.
- **Boundary:** for substantial test work the orchestrator coordinates rather than writing large suites inline; small test tweaks that accompany a Trivial change may stay inline. When delegating, say so plainly (e.g. "Delegating to Test Engineer…") and forward the request with full context.

This keeps the hierarchy intact: the orchestrator (or an orchestrator skill) dispatches to `test-engineer`; agents never command one another or trigger workflows upward.

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
3. **Direct action first:** do small, mechanical, or read-only tasks inline; delegate only substantial, specialized, or parallelizable work. Default to inline when unsure.
4. **Cap delegation depth:** orchestrator → specialist → at most one sideways handoff → terminal. A delegated agent does the work with tools and never re-delegates within the chain.
5. Route substantial domain work to the matching specialist per the Specialist Agent Delegation table, tier-gated (Trivial = never, Standard = inline default, Full = coordinate), on a model that fits the task (judgment → strong, mechanical → cheap).
6. Delegate substantial unit-test work to `test-engineer`; after Standard/Full-tier code changes, hand off for an updated test plan and tests. Use one structured handoff per concern and respect locked decisions.
> If anything above conflicts with these, **these win**.
