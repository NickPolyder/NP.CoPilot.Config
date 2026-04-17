---
name: documentation
description: >
  Guides the creation and maintenance of project documentation in the docs/
  folder, ensuring consistency in structure, style, and coverage whenever
  functionality changes. Coordinates with specialist agents to produce
  accurate, domain-specific documentation.
tags:
  - documentation
  - docs
  - workflow
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles, todo]
---

# Purpose

You are helping maintain project documentation in the `docs/` folder.

Your goals are to:

- Keep documentation in sync with code changes — every feature addition, modification, or removal should be reflected in docs.
- Follow the established structure and writing style of the project.
- Ensure documentation is comprehensive and actionable.
- **Consult specialist agents** for domain-specific accuracy (see Agent Consultation below).

---

# When to use this skill

Use this skill whenever:

- You add, change, or remove functionality in the codebase.
- The user asks to document something.
- You create a new feature, endpoint, page, or entity.
- Infrastructure or deployment changes are made.
- An architecture decision is recorded (coordinate with the `architecture-decision-record` skill).
- A feature plan is finalized (coordinate with the `feature-planning` skill).
- UX specifications or wireframes need to be documented.

**Rule: Always update docs/ when adding, changing, or removing functionality.**

---

# Agent consultation

Different documentation types benefit from specialist agent input. Consult the appropriate agent to ensure accuracy and completeness:

| Document Type | Primary Agent | Supporting Agents |
|---|---|---|
| Feature documentation | **product-owner** (requirements, acceptance criteria) | fullstack-developer, frontend-developer, backend-developer |
| API reference | **backend-developer** (endpoints, contracts, payloads) | architect (patterns, versioning) |
| Architecture decisions (ADRs) | **architect** (options, trade-offs, patterns) | systems-engineer, security-engineer |
| Infrastructure / deployment | **devops-engineer** (pipelines, IaC, environments) | systems-engineer (integration, networking) |
| Database / data model | **database-engineer** (schema, migrations, indexing) | backend-developer (EF Core mappings) |
| Security documentation | **security-engineer** (threats, controls, compliance) | architect (trust boundaries) |
| UX specifications | **ux-engineer** (user flows, wireframes, accessibility) | frontend-developer (implementation feasibility) |
| Test strategy / coverage | **qa-engineer** (test plans, coverage analysis) | product-owner (acceptance criteria) |
| Service Fabric topology | **service-fabric-engineer** (cluster config, services) | devops-engineer (deployment), systems-engineer (integration) |

**How to consult:** When creating or updating a document of a given type, invoke the primary agent to review the technical content for accuracy. If the document spans multiple domains, involve the supporting agents as well.

---

# Documentation structure

Most projects should follow a structure like:

```
docs/
├── README.md                    (main index with table of contents)
├── features/                    (feature documentation)
│   ├── README.md                (feature docs index)
│   └── {feature}.md
├── bugs/                        (bug fix documentation)
│   ├── README.md                (bug docs index)
│   └── {bug}.md
├── decisions/                   (architecture decision records)
│   ├── README.md                (ADR index with status summary)
│   └── {NNN}-{title}.md         (individual ADRs, numbered sequentially)
├── api/                         (API documentation)
│   ├── README.md                (API docs index)
│   └── {service-or-area}.md
├── ux/                          (UX specifications)
│   ├── README.md                (UX docs index)
│   └── {feature-or-flow}.md
└── infra/                       (infrastructure/deployment docs)
    ├── README.md                (infra docs index)
    └── {topic}.md
```

If the project already has a `docs/` folder, follow its existing structure. If not, create one following this pattern.

### Placement rules

| Change Type | Document Location | Agent to Consult |
|---|---|---|
| New feature or module | `docs/features/{feature}.md` | product-owner, relevant developer |
| Bug fix | `docs/bugs/{bug}.md` | backend-developer or relevant developer |
| API changes | `docs/api/{service-or-area}.md` | backend-developer |
| Domain model changes | `docs/features/domain-model.md` | database-engineer, architect |
| Architecture decision | `docs/decisions/{NNN}-{title}.md` | architect (use `architecture-decision-record` skill) |
| UX specification | `docs/ux/{feature-or-flow}.md` | ux-engineer |
| Deployment changes | `docs/infra/deployment.md` | devops-engineer |
| Service Fabric topology | `docs/infra/service-fabric.md` | service-fabric-engineer |
| Server/network config | `docs/infra/` (appropriate file) | systems-engineer |
| Security controls | `docs/infra/security.md` | security-engineer |
| Test strategy | `docs/features/{feature}-test-strategy.md` | qa-engineer (use `test-strategy` skill) |

---

# Document templates

## Standard document template

Every document follows this structure:

```markdown
# {Title}

{One-paragraph description of what this document covers and why it exists.}

## {Major Section}

{Description and context.}

### {Subsection}

{Details, steps, or reference data.}

| Column 1 | Column 2 | Column 3 |
|---|---|---|
| Data | Data | Data |

```{language}
// Code examples where relevant
```
```

## API documentation template

Use this template for API endpoint documentation in `docs/api/`:

```markdown
# {Service/Area} API Reference

{Overview of this API area and its purpose.}

## Endpoints

### `{METHOD} /api/{resource}`

**Description:** {What this endpoint does.}

**Authentication:** {Required auth scheme.}

**Request:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| {name} | {type} | {yes/no} | {description} |

**Request body:**

```json
{
  "field": "value"
}
```

**Response (200):**

```json
{
  "field": "value"
}
```

**Error responses:**

| Status | Description |
|---|---|
| 400 | {validation error details} |
| 401 | {unauthorized} |
| 404 | {not found} |
```

## Architecture Decision Record (ADR) template

Use this template for ADRs in `docs/decisions/`. Prefer using the `architecture-decision-record` skill which provides a guided workflow.

```markdown
# {NNN}. {Decision Title}

**Date:** {YYYY-MM-DD}
**Status:** {Proposed | Accepted | Deprecated | Superseded by [NNN]}
**Deciders:** {agents or roles involved}

## Context

{What is the issue? What forces are at play? Include technical and business context.}

## Options Considered

### Option 1: {Name}

{Description.}

| Pros | Cons |
|---|---|
| {pro} | {con} |

### Option 2: {Name}

{Description.}

| Pros | Cons |
|---|---|
| {pro} | {con} |

## Decision

{Which option was chosen and why.}

## Consequences

- {Positive consequence}
- {Negative consequence or trade-off}
- {Follow-up actions needed}
```

## UX specification template

Use this template for UX documentation in `docs/ux/`:

```markdown
# {Feature/Flow} — UX Specification

{Overview of the user experience being specified.}

## User Personas

{Who are the target users for this feature?}

## User Flow

{Step-by-step user journey. Use numbered lists or a flow diagram.}

1. User navigates to {page}
2. User sees {component/state}
3. User performs {action}
4. System responds with {feedback}

## Wireframe Notes

{Describe the layout, key components, and interaction patterns. Reference wireframe files if available.}

## Accessibility Requirements

| Requirement | Implementation |
|---|---|
| Keyboard navigation | {details} |
| Screen reader support | {details} |
| Color contrast | {WCAG AA minimum} |
| Focus management | {details} |

## Edge Cases

| Scenario | Expected Behavior |
|---|---|
| {scenario} | {behavior} |
```

---

# Writing style

- **Audience**: Developers working on or deploying this project.
- **Voice**: Active, direct. "You can add an ingredient" not "Ingredients may be added".
- **Structure**: High-level overview first, then implementation specifics.
- **Step-by-step**: Use numbered lists for workflows and procedures.
- **Tables**: Use for structured reference data (fields, values, config settings).
- **Code blocks**: Include for configuration, commands, and technical details.
- **Cross-references**: Link between related docs and reference related ADRs.
- **Specific**: Reference actual page URLs, field names, enum values, and file paths.
- **Explain why**: Not just "how" but "why" a design choice was made.

---

# Updating existing docs

When modifying an existing feature:

1. Find the relevant doc in `docs/`.
2. Update the affected sections to reflect the change.
3. If new sections are needed, add them following the existing structure.
4. Update any tables or reference data that changed.
5. Update the index (`docs/README.md`) if a new document was added.
6. Check if an existing ADR is affected — if so, update its status or create a superseding ADR.
7. Consult the relevant specialist agent (see Agent Consultation) if the changes affect their domain.

---

# Creating a new feature doc

1. Create `docs/features/{feature}.md`.
2. Follow the standard document template above.
3. Consult the **product-owner** agent for requirements and acceptance criteria.
4. Consult the relevant **developer agent** (fullstack, frontend, backend) for technical details.
5. Include:
   - Overview of the feature and its purpose.
   - User workflows (browsing, creating, editing, deleting).
   - Input fields and requirements (tables).
   - API endpoints involved (link to `docs/api/` if detailed reference exists).
   - Domain entities and relationships.
   - Any special behaviour or edge cases.
   - Related ADRs (link to `docs/decisions/` entries).
6. Add an entry to `docs/features/README.md`.
7. Add an entry to `docs/README.md`.

---

# Creating a new infrastructure doc

1. Create `docs/infra/{topic}.md`.
2. Consult the **devops-engineer** agent for pipeline/deployment details.
3. Consult the **systems-engineer** agent for integration and networking aspects.
4. Include:
   - Purpose and context.
   - Scripts or tools involved (with usage examples).
   - Step-by-step procedures.
   - Environment variables and configuration (tables).
   - Network topology or architecture if relevant.
   - Troubleshooting tips.
5. Add an entry to `docs/infra/README.md`.
6. Add an entry to `docs/README.md`.

---

# Creating a new bug doc

1. Create `docs/bugs/{bug}.md`.
2. Follow the standard document template above.
3. Include:
   - Summary of the bug (symptoms, impact, affected area).
   - Root cause analysis.
   - The fix applied and why.
   - Test cases added to prevent regression.
   - Any related issues or future improvements identified.
4. Add an entry to `docs/bugs/README.md`.
5. Add an entry to `docs/README.md`.

---

# Cross-references to other skills

This skill works alongside other skills in the workflow:

| Skill | Relationship |
|---|---|
| `architecture-decision-record` | ADRs created by that skill should be stored in `docs/decisions/`. This skill ensures the ADR index is maintained. |
| `feature-planning` | Feature plans produced by that skill can be used as the basis for feature documentation. |
| `requirement-breakdown` | Requirement breakdowns inform what needs to be documented — each epic/story may need feature docs. |
| `test-strategy` | Test strategies can be documented alongside their features or in dedicated test docs. |
| `security-audit` | Security assessment findings may require documentation updates (security controls, threat model docs). |

---

# Checklist for documentation changes

1. ☐ Relevant doc updated or created in `docs/`
2. ☐ Index (`docs/README.md`) updated if a new doc was added
3. ☐ Sub-folder index updated if a new doc was added
4. ☐ Writing style matches existing docs (active voice, tables for data, code blocks)
5. ☐ Cross-references added where relevant (related docs, ADRs, API references)
6. ☐ All user-visible changes (UI, API, config) are documented
7. ☐ Specialist agent consulted for domain-specific accuracy
8. ☐ ADR created or updated if an architecture decision was involved
9. ☐ UX specification created if user-facing flows changed
10. ☐ API documentation updated if endpoints changed
