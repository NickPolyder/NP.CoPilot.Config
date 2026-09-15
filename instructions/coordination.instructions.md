# Agent & Skill Coordination

> **Intent (anchor):** Define how global, project, and local instructions coordinate with skills, agents, and tools. This file is the single canonical source for precedence, the invocation hierarchy, and handoff rules.
> **Always:** Apply the repository conflict-resolution policy; preserve legal User → Skill → Agent → Tools flow; take direct action on small tasks and delegate only substantial, specialized, or parallelizable work to the matching specialist on a task-appropriate model; use structured handoffs.
> **Never:** Let an agent invoke an entry workflow, allow an active entry workflow to nest, delegate reflexively on a domain keyword, or let a delegated specialist spawn another agent.
> **Precedence:** Copilot combines applicable global, project, and local guidance. When that guidance conflicts, treat the most repository-specific instruction as authoritative unless a higher-priority system or safety constraint prevents it; within a file, the **Final Rules (Anchor)** win.

## Configuration Precedence

Copilot combines applicable instruction sources. This repository's conflict-resolution policy is:

1. **Global** (`~/.copilot/`) — these files, plus global agents and skills. Always active.
2. **Project** (`.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`) — repo-specific overrides: framework, infra, build commands, feature toggles.
3. **Local** (gitignored per-user files) — personal overrides that don't belong in source control.

When loaded guidance conflicts, agents should treat project-specific direction as more authoritative than global guidance, and local personal preferences as more authoritative than project guidance, unless a higher-priority system or safety constraint prevents it. When a project defines specific tooling (e.g., Angular, PostgreSQL, Azure DevOps), agents and skills should respect those choices and skip irrelevant guidance.

## Skill Composition

Skills and agents follow a bounded composition model:

```text
User
  -> one entry workflow or an atomic skill invoked directly
      -> zero or more atomic phase skills
          -> agents
              -> tools
```

| Role | Skills | Rule |
|---|---|---|
| Entry workflow | `prd-workflow`, `feature-planning` | Owns end-to-end sequencing and approval gates. Only one may be active. |
| Thin coordinator | `dependency-audit`, `test-gap-analysis` | Sequences its named atomic skills behind one approval gate. |
| Atomic phase | `codebase-research`, `feature-design-doc`, `task-breakdown`, `implementation-runner`, `dependency-audit-report`, `dependency-upgrade-execution`, `test-gap-audit`, `test-gap-fill` | Performs one bounded phase and never invokes an entry workflow. |
| Terminal workflow | `git-commit-review`, `full-code-review` | Starts only through direct user invocation or after a prior workflow has completed its own state. It never runs inside an active workflow. |

Rules:

1. A user may invoke an entry workflow, thin coordinator, atomic phase, or terminal workflow directly.
2. An active entry workflow or thin coordinator may sequence only its documented atomic phase skills and agents.
3. Skill-to-skill edges must be acyclic and depth-bounded; an atomic phase never invokes an entry workflow or coordinator.
4. A completed workflow may recommend or explicitly hand off to a separate terminal workflow, such as `git-commit-review`; this is a new workflow, not nesting.
5. **Agent → Tools** — agents use tools (edit, search, run commands) but do not invoke skills. If an agent identifies work needing a skill, it recommends that skill to the user or returns the recommendation to its invoking workflow.

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
| One logical change owns both an API contract and its consuming Angular/Blazor UI | `fullstack-developer` |
| Node.js / TypeScript / Next.js dashboards and small web apps | `node-developer` |
| Python — MCP servers, FastAPI, async services, automation | `python-developer` |
| Data modeling, migrations, query optimization, data integrity | `database-engineer` |
| Azure Service Fabric — Reliable Services/Actors, clusters, upgrades, partitioning, and platform diagnostics | `service-fabric-engineer` |
| Service integration, API contracts, messaging, resilience, application/service observability, distributed design | `systems-engineer` |
| CI/CD, IaC, containers, cloud infrastructure, and deployment/monitoring infrastructure | `devops-engineer` |
| Security — threat modeling, vulnerability analysis, authn/authz, secure coding | `security-engineer` |
| Test strategy, coverage analysis, pyramid balance, edge-case discovery | `qa-engineer` |
| Deterministic unit tests, test plans, mutation/branch/condition coverage | `test-engineer` |
| Code review — bugs, logic errors, security, pattern violations | `code-reviewer` |
| Requirements → user stories, acceptance criteria, backlog shaping | `product-owner` |
| UX — research, wireframes, prototypes, usability, design systems, IA | `ux-engineer` |
| Documentation writing craft — audience, structure, clarity, editing, examples | `technical-writer` |

**Multi-domain work:** the orchestrator sequences only the specialists needed for substantial work or a required workflow gate; the routing table is not a mandatory agent chain. Specialists return results and additional-domain recommendations to the orchestrator rather than dispatching each other. Use `fullstack-developer` only when the same logical change owns both its API contract and consuming UI; otherwise split substantial work across `frontend-developer` and `backend-developer`. `systems-engineer` owns application/service observability, `devops-engineer` owns deployment and monitoring infrastructure, and `service-fabric-engineer` owns Service Fabric diagnostics.

**Stays on the orchestrator (do it inline):** single-file lookups, reading files, mechanical edits, answering questions from context, Trivial-tier changes, and the coordination/synthesis of specialist output. When unsure whether a task is big enough to delegate, **default to doing it inline** unless it is genuinely substantial, needs specialized judgment, or is parallelizable — reflexive over-delegation (and the loops it causes) is the more common failure than under-delegation.

## Delegation Discipline & Loop Prevention

Delegation must terminate. The depth cap and tier gate below exist specifically to stop the "see a domain word → delegate → the sub-agent re-reads the same mandate → re-delegates → loop" failure.

**Delegation depth cap (hard):**

- **Depth 0 → 1:** the orchestrator delegates a substantial task to a specialist. Normal.
- **Depth 1 is terminal:** the specialist completes its assigned work with tools and never delegates again.
- **Additional domains:** return the specific question, evidence, and any blocker to the orchestrator. It may dispatch a separate, bounded specialist task; do not bounce the same unresolved objective between agents.

**A delegated agent is the doer.** Once you receive delegated work, your job is to *do it with tools* — not to route it onward. The "Defer to / Consult" lists in agent definitions are **advisory**: they tell you whose input to surface as a recommendation, not a trigger to spawn another agent.

**Tier gate (from the Development Workflow):**

| Tier | Delegation posture |
|------|--------------------|
| **Trivial** | Never delegate. Do it inline. |
| **Standard** | Inline by default. Delegate only for genuinely specialized judgment or substantial multi-step work. |
| **Full** | Coordinate/delegate across specialists as designed. |

This reconciles with the CLI's built-in guidance: **direct action first** — any task completable in a few tool calls is done inline; delegation is reserved for substantial, specialized, or parallelizable work.

## Test Work Delegation

Substantial unit-test authoring is owned by the `test-engineer` agent. Delegate based on test complexity, uncertainty, and need for separate context, not a testing keyword or the implementation tier alone. Small regression tests that travel with a contained change stay inline.

- **Delegate to `test-engineer`** for substantial test authoring, test plans, test-quality reviews, coverage improvements, or CI failure analysis that benefits from specialist context. Honor explicit requests for that agent.
- **After code changes**, keep tests with the behavior they cover. Make small, clear updates inline; hand substantial test work to `test-engineer` with the changed code, expected behavior, and existing test conventions. Preserve independent-review gates required by an active workflow.
- **Broader test scope stays with the strategist.** Route test *strategy* across the pyramid (integration/E2E/performance, risk-based planning) to `qa-engineer`; route durable strategy or retrospective gap-filling to the `test-strategy` / `test-gap-*` skills. `test-engineer` owns concrete deterministic unit tests.
- **Boundary:** for substantial test work the orchestrator coordinates rather than writing large suites inline; small test updates may stay inline in any tier. When delegating, say so plainly (e.g. "Delegating to Test Engineer…") and forward the request with full context.

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

1. Treat applicable global, project, and local instructions as combined; resolve conflicts toward the most repository-specific guidance unless a higher-priority system or safety constraint prevents it.
2. Follow the bounded composition model: User → one entry workflow or atomic skill → atomic phase skills → agents → tools.
3. **Direct action first:** do small, mechanical, or read-only tasks inline; delegate only substantial, specialized, or parallelizable work. Default to inline when unsure.
4. **Cap delegation depth:** orchestrator → specialist → tools. A delegated agent never spawns another agent; return additional-domain needs to the orchestrator.
5. Route substantial domain work to the matching specialist per the Specialist Agent Delegation table, tier-gated (Trivial = never, Standard = inline default, Full = coordinate), on a model that fits the task (judgment → strong, mechanical → cheap).
6. Keep tests with changed behavior; delegate substantial unit-test work to `test-engineer` and keep small regression updates inline regardless of tier. Preserve explicit workflow review gates, use one structured handoff per concern, and respect locked decisions.
> If anything above conflicts with these, **these win**.
