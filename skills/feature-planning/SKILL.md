---
name: feature-planning
description: >
  Multi-agent feature planning workflow that coordinates from requirements
  through architecture, UX design, implementation planning, test strategy,
  security review, and deployment considerations. Produces a comprehensive
  feature plan document.
tags:
  - planning
  - feature
  - multi-agent
  - workflow
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles, todo]
---

# Purpose

You are conducting a comprehensive feature planning process.

Your goals are to:

- **Gather and clarify requirements** from a product perspective.
- **Assess UX needs** — user flows, wireframe considerations, and usability.
- **Evaluate architectural impact** — how the feature fits into the system.
- **Plan implementation** — what needs to be built, by whom, in what order.
- **Define test strategy** — what to test and how.
- **Identify security considerations** — threats and mitigations.
- **Plan deployment** — infrastructure needs and rollout strategy.
- **Produce a comprehensive feature plan** that the team can execute against.

---

# When to use this skill

Use this skill whenever:

- A new feature needs to be planned from scratch.
- The user asks to "plan a feature", "scope out", or "design" a significant piece of work.
- A feature spans multiple domains (frontend, backend, database, infrastructure).
- The team needs a shared understanding of what will be built and how.

Do **not** use this skill for:

- Simple tasks that don't need multi-agent planning.
- Bug fixes (just fix them).
- Pure architecture decisions (use the `architecture-decision-record` skill).
- Pure requirement breakdowns without technical planning (use the `requirement-breakdown` skill).

---

# Planning process

## Phase 1: Requirements (Product Owner perspective)

Analyze the feature from a product perspective:

1. **What** is the feature? (Clear description)
2. **Who** benefits? (User personas)
3. **Why** does it matter? (Business value)
4. **What does success look like?** (Measurable outcomes)
5. **What's in/out of scope?** (Boundaries)

Ask clarifying questions for any ambiguity before proceeding.

Output:

```markdown
## Requirements

### Feature Description
{What the feature does and why it matters}

### Target Users
{Who benefits and their primary use cases}

### Business Value
{Why this is worth building — metrics, outcomes}

### Scope
- **In scope:** {list}
- **Out of scope:** {list}

### Success Metrics
- {Metric 1: e.g., "80% of users complete the flow without errors"}
- {Metric 2: e.g., "API response time < 200ms at p95"}
```

## Phase 2: UX Analysis (UX Engineer perspective)

Assess the user experience:

1. **User flow** — how does the user interact with this feature?
2. **Key screens/interactions** — what are the main touchpoints?
3. **States** — what states need design? (empty, loading, error, success, edge cases)
4. **Accessibility** — any specific a11y requirements?
5. **Research needs** — does this need user research before implementation?

Output:

```markdown
## UX Analysis

### User Flow
1. {Step 1: User navigates to...}
2. {Step 2: User sees...}
3. {Step 3: User interacts with...}
4. {Step 4: System responds with...}

### Key Screens
- {Screen 1}: {purpose and key elements}
- {Screen 2}: {purpose and key elements}

### States to Design
| Component | Empty | Loading | Error | Success | Edge Case |
|---|---|---|---|---|---|
| {component} | {state} | {state} | {state} | {state} | {state} |

### Accessibility Requirements
- {Requirement 1}
- {Requirement 2}

### UX Research Needs
- {Research question or "None — follows established patterns"}
```

**Requirements and UX complete. Present both sections to the user:**

> **Phases 1-2 complete (Requirements + UX). Review the scope and user flows above. Approve moving to architecture and implementation planning? (yes / no / adjust)**

---

## Phase 3: Architecture Assessment (Architect perspective)

Evaluate the architectural impact:

1. **Affected components** — what parts of the system are involved?
2. **New components** — what needs to be created?
3. **Pattern alignment** — does this follow or deviate from existing patterns?
4. **Data flow** — how does data move through the system?
5. **Integration points** — any external system interactions?
6. **Technical decisions** — any architectural choices to make? (create ADRs if significant)

Output:

```markdown
## Architecture Assessment

### System Impact
{Which parts of the system are affected and how}

### Component Map
```
{Diagram or description of involved components}
```

### New Components
- {Component 1}: {purpose}
- {Component 2}: {purpose}

### Pattern Alignment
{Does this follow existing patterns or need new ones?}

### Architectural Decisions Needed
- {Decision 1: create ADR if significant}
- {"None — follows established patterns"}

### Data Flow
{How data moves from input to storage to output}
```

## Phase 4: Technical Implementation Plan (Developer perspectives)

Plan the actual implementation:

1. **Backend work** — APIs, services, domain logic, data access.
2. **Frontend work** — components, state management, routing.
3. **Database work** — schema changes, migrations, indexes.
4. **Integration work** — external services, messaging, events.
5. **Infrastructure work** — new resources, configuration, pipelines.
6. **Service Fabric work** — if the feature involves SF services.

For each area, define:
- What needs to be built
- Which agent is responsible
- Key technical decisions
- Dependencies on other areas

Output:

```markdown
## Implementation Plan

### Backend ({backend-developer})
- {Task 1: e.g., "Create OrderExportService with PDF/CSV generation"}
- {Task 2: e.g., "Add GET /api/orders/export endpoint"}

### Frontend ({frontend-developer} or {fullstack-developer})
- {Task 1: e.g., "Create ExportButton component with format selection"}
- {Task 2: e.g., "Add date range picker for export filtering"}

### Database ({database-engineer})
- {Task 1: e.g., "Add index on Orders(UserId, CreatedAt) for export queries"}
- {"No database changes needed"}

### Integration ({systems-engineer})
- {Task 1: e.g., "Configure message for async PDF generation"}
- {"No integration changes needed"}

### Infrastructure ({devops-engineer})
- {Task 1: e.g., "Add blob storage for generated export files"}
- {"No infrastructure changes needed"}

### Implementation Order
1. {Phase 1: Database + API contract}
2. {Phase 2: Backend services + Frontend components}
3. {Phase 3: Integration + Polish}
```

**Architecture and implementation plan complete. Present both sections to the user:**

> **Phases 3-4 complete (Architecture + Implementation Plan). Review the component design and task breakdown. Approve moving to test strategy, security, and deployment planning? (yes / no / adjust)**

---

## Phase 5: Test Strategy (QA Engineer perspective)

Define the testing approach:

1. **Unit tests** — what logic needs unit testing?
2. **Integration tests** — what API/service interactions to test?
3. **E2E tests** — what critical user journeys need E2E coverage?
4. **Edge cases** — what could go wrong?
5. **Performance** — any performance testing needed?

Output:

```markdown
## Test Strategy

### Test Coverage Plan
| Level | What to Test | Responsibility |
|---|---|---|
| Unit | {areas} | {developer agent} |
| Integration | {areas} | {developer agent} |
| E2E | {journeys} | `qa-engineer` |

### Key Edge Cases
| Scenario | Expected Behavior | Priority |
|---|---|---|
| {edge case} | {behavior} | High/Medium/Low |

### Performance Testing
- {Performance requirement and how to test it, or "Not needed"}
```

## Phase 6: Security Review (Security Engineer perspective)

Identify security considerations:

1. **Authentication** — does this feature need auth?
2. **Authorization** — who can access what?
3. **Data sensitivity** — any PII or sensitive data?
4. **Input validation** — what inputs need validation?
5. **Threats** — any specific threats to consider?

Output:

```markdown
## Security Considerations

### Authentication & Authorization
- {Auth requirements for this feature}

### Data Sensitivity
- {PII or sensitive data involved}

### Input Validation
- {Validation rules for user inputs}

### Threats & Mitigations
| Threat | Risk | Mitigation |
|---|---|---|
| {threat} | High/Med/Low | {mitigation} |

### Security Actions
- {Action 1: e.g., "Add authorization policy for export endpoint"}
- {"No security concerns — follows established patterns"}
```

## Phase 7: Deployment & Infrastructure (DevOps perspective)

Plan the deployment:

1. **New infrastructure** — any new resources needed?
2. **Configuration** — new settings or secrets?
3. **Migration** — any data migration needed?
4. **Rollout strategy** — how to deploy safely?
5. **Monitoring** — what to monitor post-deployment?

Output:

```markdown
## Deployment Plan

### Infrastructure Changes
- {New resource or "None"}

### Configuration
- {New settings, secrets, or "None"}

### Migration Plan
- {Data migration steps or "No migration needed"}

### Rollout Strategy
- {How to deploy: feature flag, canary, big-bang}

### Monitoring
- {What to monitor post-deployment}
- {Alerts to configure}
```

---

# Consolidated output

After completing all phases, compile into a single feature plan:

```markdown
# Feature Plan: {Feature Name}

**Date:** {date}
**Status:** Draft / Approved
**Owner:** {who owns this feature}

## 1. Requirements
{From Phase 1}

## 2. UX Analysis
{From Phase 2}

## 3. Architecture
{From Phase 3}

## 4. Implementation Plan
{From Phase 4}

## 5. Test Strategy
{From Phase 5}

## 6. Security
{From Phase 6}

## 7. Deployment
{From Phase 7}

## 8. Open Questions
{Unresolved questions from any phase}

## 9. Estimated Effort
| Area | Agent | Effort |
|---|---|---|
| Backend | `backend-developer` | {S/M/L} |
| Frontend | `frontend-developer` | {S/M/L} |
| Database | `database-engineer` | {S/M/L} |
| ... | ... | ... |
```

---

# Storage

Save the feature plan to `docs/features/{feature-name}-plan.md` or present it to the user for review, depending on the project's documentation structure.

---

# Related skills

- **`requirement-breakdown`** — for deeper story-level breakdown of the requirements.
- **`architecture-decision-record`** — for significant architectural decisions identified during planning.
- **`security-audit`** — for deeper security assessment if needed.
- **`test-strategy`** — for deeper test planning if needed.
- **`documentation`** — for documenting the feature after implementation.

---

# Checklist

1. ☐ Requirements gathered and clarified (no ambiguity)
2. ☐ UX analysis completed (user flows, states, accessibility)
3. ☐ Architecture assessed (impact, components, patterns, data flow)
4. ☐ Implementation planned (tasks per agent, dependencies, order)
5. ☐ Test strategy defined (pyramid, edge cases, performance)
6. ☐ Security reviewed (auth, data sensitivity, threats)
7. ☐ Deployment planned (infra, config, rollout, monitoring)
8. ☐ Open questions documented
9. ☐ Feature plan presented to user for review

---

# Rules

- Complete all 7 phases — skipping a phase leads to blind spots.
- Ask clarifying questions in Phase 1 before proceeding — don't assume.
- Every implementation task must have a responsible agent assigned.
- Security is never "not applicable" — at minimum, confirm existing patterns cover this feature.
- If a significant architectural decision is needed, create an ADR using the `architecture-decision-record` skill.
- Present the consolidated plan to the user before considering planning complete.
- Keep the plan actionable — developers should be able to start working from it.
