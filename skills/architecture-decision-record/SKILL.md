---
name: architecture-decision-record
description: >
  Guides the creation of structured Architecture Decision Records (ADRs) that
  capture context, options evaluated, decisions made, and consequences. Stores
  ADRs in the docs/decisions/ folder for long-term reference.
tags:
  - architecture
  - decisions
  - documentation
  - workflow
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles, todo]
---

# Purpose

You are creating an Architecture Decision Record (ADR).

Your goals are to:

- **Capture the context** behind an architectural decision so future developers understand *why* a choice was made.
- **Enumerate and evaluate options** with pros, cons, and trade-offs.
- **Document the decision** and its expected consequences.
- **Store the ADR** in a consistent location for long-term reference.
- **Consult specialist agents** for domain-specific input on the decision.

---

# When to use this skill

Use this skill whenever:

- A significant architectural decision is being made or proposed.
- The team is evaluating multiple technical approaches.
- A technology choice needs to be documented (framework, library, pattern, tool).
- An existing architectural decision is being revisited or superseded.
- The user asks to "document a decision", "create an ADR", or "record why we chose X".

Examples of decisions that warrant an ADR:

- Choosing a state management approach (NgRx vs signals vs services)
- Selecting a messaging technology (RabbitMQ vs Azure Service Bus)
- Deciding on a data access pattern (repository pattern vs direct DbContext)
- Choosing a deployment strategy (Kubernetes vs Service Fabric vs App Service)
- Selecting an authentication approach (ASP.NET Identity vs external IdP)
- Changing a cross-cutting concern (logging framework, error handling strategy)

Do **not** use this skill for:

- Trivial implementation choices that don't affect architecture.
- Bug fixes or feature implementation (use other workflows).
- Documentation of existing features (use the `documentation` skill).

---

# ADR process

## Step 1: Identify the decision

Clearly state what is being decided:

1. What architectural question needs answering?
2. What triggered this decision? (new feature, tech debt, scaling issue, team feedback)
3. What constraints exist? (timeline, budget, team skills, existing systems)
4. Who are the stakeholders?

## Step 2: Gather context

Before evaluating options, understand the landscape:

1. **Current state** — how does the system work today?
2. **Requirements** — what must the solution provide? (functional and non-functional)
3. **Constraints** — what limits the options? (technology, compliance, team expertise)
4. **Quality attributes** — which "-ilities" matter most? (scalability, maintainability, performance, security)

Consult relevant specialist agents for domain-specific context:

| Decision Domain | Consult Agent |
|---|---|
| System structure, patterns | `architect` |
| Frontend architecture | `frontend-developer` |
| Backend patterns, .NET specifics | `backend-developer` |
| Data modeling, database choice | `database-engineer` |
| Service communication, integration | `systems-engineer` |
| Deployment, infrastructure | `devops-engineer` |
| Security implications | `security-engineer` |
| Service Fabric specifics | `service-fabric-engineer` |
| User experience impact | `ux-engineer` |
| Testability | `qa-engineer` |
| Business impact | `product-owner` |

## Step 3: Enumerate options

List all viable options (typically 2-4):

For each option, document:
- Brief description
- Pros (advantages, strengths)
- Cons (disadvantages, risks)
- Effort estimate (relative: low/medium/high)
- Risk level (what could go wrong)

## Step 4: Evaluate and decide

Compare options using a decision matrix:

```markdown
| Criterion | Weight | Option A | Option B | Option C |
|---|---|---|---|---|
| {criterion 1} | High | ✅ Good | ⚠️ Partial | ❌ Poor |
| {criterion 2} | Medium | ⚠️ Partial | ✅ Good | ✅ Good |
| {criterion 3} | Low | ✅ Good | ✅ Good | ⚠️ Partial |
```

Make a recommendation based on the evaluation. If the decision is close, present to the user for final call.

## Step 5: Document the ADR

Write the ADR using the template below and save it.

---

# ADR template

```markdown
# ADR-{number}: {Title}

**Status:** {Proposed | Accepted | Deprecated | Superseded by ADR-{N}}
**Date:** {YYYY-MM-DD}
**Decision Makers:** {who was involved}

## Context

{What is the issue that we're seeing that is motivating this decision or change?
What is the current state? What are the requirements and constraints?}

## Decision Drivers

- {driver 1: e.g., "Need to support 10K concurrent users"}
- {driver 2: e.g., "Team has deep experience with .NET"}
- {driver 3: e.g., "Must integrate with existing Service Bus infrastructure"}

## Options Considered

### Option 1: {Name}

{Description of the approach.}

**Pros:**
- {advantage 1}
- {advantage 2}

**Cons:**
- {disadvantage 1}
- {disadvantage 2}

### Option 2: {Name}

{Description of the approach.}

**Pros:**
- {advantage 1}
- {advantage 2}

**Cons:**
- {disadvantage 1}
- {disadvantage 2}

### Option 3: {Name} (if applicable)

{...}

## Decision Matrix

| Criterion | Weight | Option 1 | Option 2 | Option 3 |
|---|---|---|---|---|
| {criterion} | High/Med/Low | ✅/⚠️/❌ | ✅/⚠️/❌ | ✅/⚠️/❌ |

## Decision

**Chosen option: {Option N} — {title}**

{Justification. Why is this option the best given the context and constraints?
Reference the decision matrix and specific drivers that tipped the balance.}

## Consequences

### Positive
- {positive consequence 1}
- {positive consequence 2}

### Negative
- {negative consequence / trade-off 1}
- {mitigation for the trade-off}

### Risks
- {risk 1} — Mitigation: {how to manage this risk}
- {risk 2} — Mitigation: {how to manage this risk}

## Follow-Up Actions

- [ ] {action item 1}
- [ ] {action item 2}
- [ ] {action item 3}

## Related

- {Link to related ADRs}
- {Link to related documentation}
- {Link to relevant tickets/issues}
```

---

# File storage

## Location

Store ADRs in `docs/decisions/` with sequential numbering:

```
docs/
└── decisions/
    ├── README.md          (index of all ADRs)
    ├── 0001-use-cqrs-pattern.md
    ├── 0002-choose-angular-over-react.md
    └── 0003-adopt-service-fabric.md
```

## Naming convention

- File: `{NNNN}-{kebab-case-title}.md`
- Number: Zero-padded 4-digit sequential (0001, 0002, ...)
- Title: Verb-noun format when possible ("use-cqrs", "adopt-service-fabric", "replace-redis-with-cosmos")

## Index maintenance

After creating an ADR, update `docs/decisions/README.md`:

```markdown
# Architecture Decision Records

| # | Decision | Status | Date |
|---|---|---|---|
| [0001](0001-use-cqrs-pattern.md) | Use CQRS pattern for order processing | Accepted | 2026-01-15 |
| [0002](0002-choose-angular-over-react.md) | Choose Angular over React for frontend | Accepted | 2026-02-01 |
```

If `docs/decisions/` or its `README.md` doesn't exist, create them.

---

# ADR lifecycle

| Status | Meaning |
|---|---|
| **Proposed** | Under discussion, not yet decided |
| **Accepted** | Decision made and in effect |
| **Deprecated** | No longer relevant (technology removed, feature sunset) |
| **Superseded** | Replaced by a newer ADR (link to replacement) |

When superseding an ADR:
1. Update the old ADR's status to `Superseded by ADR-{N}`.
2. Reference the old ADR in the new one's "Related" section.
3. Update the index.

---

# Example output

## Input

> "We need to decide between using Redis and an in-memory cache for our application caching layer."

## Output

```markdown
# ADR-0004: Use Redis over in-memory cache for application caching

**Status:** Accepted
**Date:** 2026-04-13
**Decision Makers:** architect, backend-developer, systems-engineer

## Context

The application currently has no caching layer. API response times for product
catalog queries average 800ms due to complex database joins. We need to add
caching to reduce latency and database load. The application runs across
multiple instances behind a load balancer.

## Decision Drivers

- Multiple application instances require shared cache (in-memory is per-instance)
- Cache invalidation must be consistent across all instances
- Need to support cache-aside and distributed locking patterns
- Team has Azure infrastructure already in place

## Options Considered

### Option 1: IMemoryCache (in-memory)

Built-in .NET in-memory cache, per-process.

**Pros:**
- Zero infrastructure — no additional service to manage
- Lowest latency (in-process)
- Simplest implementation

**Cons:**
- Per-instance — cache is not shared across application instances
- Cache inconsistency across instances (stale data)
- Memory pressure on application process
- Lost on restart/deployment

### Option 2: Redis (Azure Cache for Redis)

Distributed cache service, shared across instances.

**Pros:**
- Shared across all instances — consistent cache state
- Survives application restarts
- Supports advanced patterns (pub/sub, distributed locks, sorted sets)
- Azure managed service — low operational overhead

**Cons:**
- Additional infrastructure cost (~$50-200/month for production tier)
- Network latency (1-2ms per call vs sub-ms for in-memory)
- Additional dependency (availability risk)
- Serialization overhead

## Decision Matrix

| Criterion | Weight | IMemoryCache | Redis |
|---|---|---|---|
| Cache consistency | High | ❌ Per-instance | ✅ Shared |
| Latency | Medium | ✅ Sub-ms | ⚠️ 1-2ms |
| Operational cost | Low | ✅ Free | ⚠️ $50-200/mo |
| Survivability | High | ❌ Lost on restart | ✅ Persistent |
| Scalability | High | ❌ Per-instance limits | ✅ Independent scaling |

## Decision

**Chosen option: Redis (Azure Cache for Redis)**

Multi-instance deployment makes in-memory caching unreliable — users on
different instances would see inconsistent data. Redis provides shared, consistent
caching with acceptable latency overhead. The Azure managed service minimizes
operational burden.

## Consequences

### Positive
- Consistent cache across all application instances
- Cache survives deployments and restarts
- Enables future use of distributed locking and pub/sub

### Negative
- Additional infrastructure cost (~$100/month for Standard tier)
  - Mitigation: Monitor cache hit rates; ensure ROI through reduced DB load
- Additional network hop adds 1-2ms latency per cache call
  - Mitigation: Acceptable for our use case; batch operations where possible

### Risks
- Redis availability — Mitigation: Use Standard tier with replication; implement fallback to database on cache miss
- Serialization bugs — Mitigation: Use System.Text.Json with tested serialization; add integration tests

## Follow-Up Actions

- [ ] Provision Azure Cache for Redis (Standard tier, 1GB)
- [ ] Implement IDistributedCache with Redis provider
- [ ] Add cache-aside pattern for product catalog queries
- [ ] Add cache invalidation on product updates
- [ ] Monitor cache hit rate and latency

## Related

- Related to planned performance optimization initiative
- See: docs/infrastructure/caching.md (to be created)
```

---

# Checklist

1. ☐ Decision clearly stated (what is being decided)
2. ☐ Context documented (current state, requirements, constraints)
3. ☐ Decision drivers listed (what matters most)
4. ☐ Multiple options enumerated (at least 2)
5. ☐ Pros and cons listed for each option
6. ☐ Decision matrix compares options on key criteria
7. ☐ Decision justified (why this option, referencing drivers and matrix)
8. ☐ Consequences documented (positive, negative, risks with mitigations)
9. ☐ Follow-up actions listed
10. ☐ ADR stored in `docs/decisions/{NNNN}-{title}.md`
11. ☐ Index (`docs/decisions/README.md`) updated
12. ☐ Relevant specialist agents consulted

---

# Rules

- Every ADR must have a clear decision statement — not just a discussion.
- Always present at least 2 options (even if one is "do nothing" or "keep current approach").
- Include both positive and negative consequences — no decision is without trade-offs.
- Link superseded ADRs to their replacements.
- Use the consistent file naming convention (`{NNNN}-{kebab-case}.md`).
- Consult relevant specialist agents before finalizing — don't make decisions in isolation.
- ADRs are immutable once accepted — to change a decision, create a new ADR that supersedes it.
