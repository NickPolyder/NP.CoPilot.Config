# Agent Coordination Protocol

This document defines how agents hand off work to other specialists. All agents reference this protocol in their Coordination sections.

## Handoff Format

When an agent determines that work should be handled by (or reviewed by) another specialist, it produces a structured handoff block:

```markdown
### 🔄 Handoff: {Source Agent} → {Target Agent}

**Reason:** {Why this needs the target's expertise}
**Context:** {Brief background — what was being done, what decision point was reached}
**Request:** {Specific ask — review this design, implement this component, validate this approach}
**Artifacts:** {Relevant files, code snippets, or decisions made so far}
**Constraints:** {Decisions already locked in that the target must respect}
**Priority:** {Blocking (can't proceed without this) | Advisory (input welcome but not blocking)}
```

## Handoff Rules

1. **Include enough context** — the target agent should be able to act without reading the full conversation history.
2. **Be specific** — "review this" is not a handoff. "Validate that the OrderAggregate boundary correctly encapsulates the discount calculation logic in src/Domain/Orders/Order.cs" is.
3. **Respect locked decisions** — if the architect already decided on the aggregate boundary, the backend-developer doesn't redesign it.
4. **One handoff per concern** — don't bundle multiple unrelated asks into one handoff.
5. **Return path** — when a specialist completes a handoff, they summarize their output in the same format for the requesting agent.

## Return Format

When the target agent completes work from a handoff:

```markdown
### ✅ Return: {Target Agent} → {Source Agent}

**Request:** {Original ask — one line}
**Outcome:** {What was done / decided / recommended}
**Artifacts:** {Files created/modified, decisions documented}
**Follow-ups:** {Anything the source agent or user should be aware of}
```

## Coordination Scenarios

### Sequential (Blocking)

Agent A cannot proceed until Agent B provides input:

```
Agent A works → hits domain boundary question → Handoff to Architect (blocking)
    → Architect reviews and returns decision
    → Agent A continues with the decision
```

### Advisory (Non-Blocking)

Agent A can proceed but would benefit from specialist review:

```
Agent A implements → produces security-sensitive code → Handoff to Security (advisory)
    → Security reviews in parallel
    → Findings applied as improvements (not blockers)
```

### Fan-Out (Skill Coordination)

A skill coordinates multiple agents in parallel:

```
Feature Planning skill:
    → Handoff to Architect (structure)
    → Handoff to Security (threat model)
    → Handoff to QA (test strategy)
    → Handoff to UX (user flows)
All return → Skill consolidates into plan
```

## When NOT to Hand Off

- Trivial questions within your expertise — just answer them.
- Implementation details that don't cross domain boundaries.
- Generic coding questions that any senior developer could answer.
- When the user explicitly asked YOU (not the specialist) for the work.
