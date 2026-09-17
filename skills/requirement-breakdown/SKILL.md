---
name: requirement-breakdown
description: >
  Takes a high-level requirement or feature request and systematically breaks it
  into epics, user stories with acceptance criteria, assigns work to the
  appropriate specialist agents, and identifies dependencies.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are breaking down a high-level requirement into actionable development work.

This is a standalone **backlog/story breakdown** skill. `feature-planning` and
`prd-workflow` may recommend it when deeper story detail is needed; that
recommendation is not an immediate nested invocation or an extra phase in
either workflow. It does not create architecture, design, or implementation plans.

Your goals are to:

- Transform vague or broad requirements into **specific, implementable user stories**.
- Write **testable acceptance criteria** for every story.
- **Assign stories to the appropriate specialist agents** based on the work involved.
- **Identify dependencies** between stories to determine implementation order.
- Ensure nothing is missed — including cross-cutting concerns like security, accessibility, and performance.

---

# When to use this skill

Use this skill whenever:

- The user provides a high-level feature request or requirement.
- The user asks to "break down", "plan out", or "scope" a feature.
- A product requirement needs to be translated into development tasks.
- You need to create a backlog of stories for a feature.
- `feature-planning` or `prd-workflow` needs a delegated story-level breakdown.

Do **not** use this skill for:

- Bug reports (use the bug report template directly).
- Simple tasks that don't need decomposition (e.g., "add a button").
- Architecture decisions (use the `architecture-decision-record` skill instead).
- Architecture/design implementation plans — use `feature-planning` or
  `prd-workflow`; this skill stops at backlog/story breakdown.

---

# Breakdown process

## Step 1: Understand the requirement

Before breaking anything down, fully understand what's being asked:

1. Read the requirement carefully.
2. Identify **who** the users are (personas).
3. Identify **what** they need to accomplish (goals).
4. Identify **why** it matters (business value).
5. Ask clarifying questions for any ambiguity:
   - What's in scope vs out of scope?
   - Are there existing patterns to follow?
   - What are the constraints (technical, timeline, regulatory)?
   - What does "done" look like?

**Rule: Never start breaking down a requirement you don't fully understand. Ask questions first.**

## Step 2: Identify affected domains

Identify the domain focus and likely future owner. This is a plan, not a
mandatory dispatch list; research uses `investigator`, approved changes use
`implementer`, and independent review uses `code-reviewer`.

| Domain | Agent | Signals |
|---|---|---|
| UI/Frontend | `implementer` | Page, form, component, display, responsive |
| Full-stack feature | `implementer` | End-to-end, spanning UI and API |
| Backend/API | `implementer` | Endpoint, service, domain logic, data processing |
| Database | `implementer` | Schema, migration, data model, query |
| Integration | `implementer` | External service, messaging, API contract |
| Infrastructure | `implementer` | Pipeline, deployment, environment, monitoring |
| Service Fabric | `implementer` | Actor, reliable service, partition, cluster |
| Security changes | `implementer` | Auth, encryption, access control, compliance |
| UX Design | `investigator` | User flow, wireframe, usability, research |
| Test strategy | `investigator` | Coverage, risks, scenarios |
| Test implementation | `implementer` | Approved unit, integration and E2E tests |
| Architecture | `investigator` | Structure, patterns, cross-cutting |

## Step 3: Create the epic

Structure the epic with:

```markdown
# Epic: {Title}

## Vision
{One sentence: what does success look like?}

## Business Value
{Why this matters — revenue, efficiency, compliance, user satisfaction}

## Users
{Who benefits and how — reference personas if available}

## Scope

### In Scope
- {Feature/capability 1}
- {Feature/capability 2}

### Out of Scope
- {Explicitly excluded item 1}
- {Explicitly excluded item 2}

## Success Metrics
- {Measurable outcome 1}
- {Measurable outcome 2}
```

## Step 4: Break into user stories

For each story, use INVEST criteria:

- **I**ndependent — can be developed without waiting for other stories (minimize dependencies)
- **N**egotiable — details can be refined with the team
- **V**aluable — delivers value to a user or stakeholder
- **E**stimable — team can estimate the effort
- **S**mall — can be completed in a single iteration
- **T**estable — has clear, verifiable acceptance criteria

### Story format

```markdown
## Story: {ID} — {Title}

**As a** {user type},
**I want** {goal},
**so that** {benefit}.

### Acceptance Criteria

#### AC1: {Scenario name}
**Given** {precondition}
**When** {action}
**Then** {expected outcome}

#### AC2: {Error scenario}
**Given** {precondition}
**When** {action}
**Then** {expected outcome}

### Agent Assignment
- **Primary:** `{agent-name}` — {what they implement}
- **Consult:** `{agent-name}` — {what they advise on}

### Dependencies
- Depends on: {story ID} (reason)
- Blocks: {story ID} (reason)

### Notes
- {Assumptions, constraints, or open questions}
```

### Story splitting strategies

When a story is too large, split using:

| Strategy | When to Use | Example |
|---|---|---|
| By workflow step | CRUD operations | Separate create, read, update, delete |
| By business rule | Complex validation | Each rule → own story |
| By data variation | Multiple input types | Handle each type separately |
| By interface | Multi-channel | API, UI, background job as separate stories |
| By operation | Complex flow | Happy path first, then errors, then edge cases |
| By user role | Role-based access | Admin vs regular user as separate stories |
| Spike + implement | Unknown territory | Research story → implementation story |

## Step 5: Identify cross-cutting concerns

For every feature, check these cross-cutting areas and create stories if needed:

| Concern | Question |
|---|---|
| Security | Does this need auth/authz or data protection? |
| Accessibility | Does the UI meet required access needs? |
| Performance | What load/data constraints actually apply? |
| Monitoring | Are additional dashboards/alerts needed for the promised behavior? |
| Documentation | Which existing user/developer docs are affected? |
| Testing | What behavior and risks need coverage? |
| UX Research | Is relevant user behavior supported by evidence? |
| Data migration | Does this change the schema or stored data? |
| Infrastructure | Does the outcome actually need new infrastructure/config? |

Create only justified stories, not a generic infrastructure checklist.

## Step 6: Map dependencies

Create a dependency map showing which stories must be completed before others:

```
{Story A} ──→ {Story B} ──→ {Story D}
                              ↑
{Story C} ────────────────────┘
```

Rules for dependencies:
- Minimize dependencies — prefer independent stories.
- Schema changes before code that uses them.
- API contracts before frontend that calls them.
- Shared components before features that use them.
- Security infrastructure before features that need auth.

## Step 7: Present the breakdown

Present the complete breakdown to the user for review:

```markdown
# Feature Breakdown: {Title}

## Epic
{Epic summary}

## Stories ({count})

| ID | Title | Agent | Dependencies | Priority |
|---|---|---|---|---|
| S1 | {title} | `{agent}` | None | Must |
| S2 | {title} | `{agent}` | S1 | Must |
| S3 | {title} | `{agent}` | None | Should |

## Dependency Graph
{Visual or text-based dependency map}

## Cross-Cutting Stories
{Security, accessibility, testing, docs stories}

## Open Questions
{Unresolved items that need stakeholder input}

## Suggested Implementation Order
1. {Phase 1 — foundational stories}
2. {Phase 2 — core feature stories}
3. {Phase 3 — refinement and cross-cutting}
```

---

# Example output

## Input

> "We need users to be able to export their order history as a PDF or CSV file."

## Output

```markdown
# Feature Breakdown: Order History Export

## Epic

### Vision
Users can download their order history in PDF or CSV format from the orders page.

### Business Value
Reduces support tickets for order history requests and gives users self-service data access.

### Users
- Registered customers who want to review past orders
- Accounting staff who need order data in spreadsheet format

### Scope
#### In Scope
- Export as PDF (formatted report)
- Export as CSV (raw data)
- Filter by date range before export
- Download from order history page

#### Out of Scope
- Scheduled/automated exports
- Export of other users' orders (admin)
- Custom report templates

### Success Metrics
- 80% reduction in "order history" support tickets
- Export completes in < 5 seconds for up to 1 year of orders

## Stories (7)

| ID | Title | Agent | Dependencies | Priority |
|---|---|---|---|---|
| S1 | API: Export order history endpoint | `implementer` | None | Must |
| S2 | PDF generation service | `implementer` | S1 | Must |
| S3 | CSV generation service | `implementer` | S1 | Must |
| S4 | UI: Export button and date filter | `implementer` | S1 | Must |
| S5 | UX: Export flow wireframe | `investigator` | None | Must |
| S6 | Test strategy for export | `investigator` | S1 | Should |
| S7 | Security: Authorize export access | `implementer` | S1 | Must |

### S1 — API: Export order history endpoint

**As a** registered customer,
**I want** an API endpoint that returns my order history in a requested format,
**so that** the frontend can trigger exports.

#### AC1: Successful CSV export
**Given** I am authenticated and have 10 orders
**When** I request GET /api/orders/export?format=csv&from=2025-01-01&to=2025-12-31
**Then** I receive a 200 response with Content-Type: text/csv and a file containing my 10 orders

#### AC2: Successful PDF export
**Given** I am authenticated and have 10 orders
**When** I request GET /api/orders/export?format=pdf&from=2025-01-01&to=2025-12-31
**Then** I receive a 200 response with Content-Type: application/pdf

#### AC3: No orders in range
**Given** I am authenticated and have no orders in the requested date range
**When** I request the export endpoint
**Then** I receive a 200 response with an empty result (CSV with headers only, PDF with "No orders found")

#### AC4: Unauthorized access
**Given** I am not authenticated
**When** I request the export endpoint
**Then** I receive a 401 Unauthorized response

**Primary:** `implementer`
**Consult:** `investigator` if authorization or large-query behavior remains uncertain

## Dependency Graph

S5 (UX wireframe) ──→ S4 (UI)
                        ↑
S1 (API endpoint) ──→ S2 (PDF service)
         │          ──→ S3 (CSV service)
         │          ──→ S4 (UI)
         │          ──→ S7 (Security)
         └──────────→ S6 (Test strategy)

## Open Questions
1. Maximum date range for export? (Performance concern for users with many orders)
2. Should PDF include company branding/logo?
3. Rate limiting on export endpoint to prevent abuse?
```

---

# Checklist

1. ☐ Requirement fully understood (no ambiguity remaining)
2. ☐ Epic created with vision, value, scope, and success metrics
3. ☐ All stories follow INVEST criteria
4. ☐ Every story has testable acceptance criteria (Given/When/Then)
5. ☐ Error and edge case scenarios included in acceptance criteria
6. ☐ Each story assigned to appropriate specialist agent(s)
7. ☐ Cross-cutting concerns addressed (security, accessibility, performance, testing)
8. ☐ Dependencies identified and minimized
9. ☐ Implementation order suggested
10. ☐ Open questions documented for stakeholder input

---

# Rules

- Never break down a requirement you don't fully understand — ask questions first.
- Every story must have a clear "so that" value statement.
- Acceptance criteria must be specific and testable — no vague adjectives.
- Always include error and edge case scenarios, not just the happy path.
- Assign stories to the most appropriate specialist agent.
- Minimize dependencies between stories to enable parallel work.
- Document assumptions explicitly — hidden assumptions are the most expensive mistakes.
- Present the breakdown for review before considering it final.

---
