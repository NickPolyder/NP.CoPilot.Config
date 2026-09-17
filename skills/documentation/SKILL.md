---
name: documentation
description: >
  Guides the creation and maintenance of project documentation in the docs/
  folder for requested documentation work. Keeps structure, factual accuracy,
  indexes and code references consistent without requiring a writing handoff
  for a small related edit.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are helping maintain project documentation in the `docs/` folder.

Your goals are to:

- Update affected documentation when user-visible behavior or operational contracts change.
- Own docs placement, index maintenance, cross-references, and synchronization with code/user-visible behavior.
- Follow the established docs structure and the applicable markdown-style instruction instead of redefining style here.
- Ensure documentation is comprehensive and actionable.
- Resolve factual uncertainty proportionally; recommend separate deep ADR, test, or security work only when needed.

---

# When to use this skill

Use this skill for a requested substantial documentation task or a workflow's
explicit documentation deliverable. Small related edits stay inline.
Examples of documentation work include:

- You add, change, or remove functionality in the codebase.
- The user asks to document something.
- You create a new feature, endpoint, page, or entity.
- Infrastructure or deployment changes are made.
- An architecture decision is recorded; recommend `architecture-decision-record` for ADR content and use this skill for placement, index, and sync.
- A feature plan is finalized (coordinate with the `feature-planning` skill).
- UX specifications or wireframes need to be documented.

Do not create a document solely because an internal implementation detail changed.

---

# Agent consultation

Reuse facts already established by the implementation and repository evidence.
When separate context is useful, assign unresolved domain questions to
`investigator`, or substantial authorized drafting/restructuring to `implementer`.
Include only relevant `skills/domain-guidance.md` sections and the document's
audience, purpose and write scope. Neither assignment requires the other.

---

# Documentation structure

This skill owns where docs live, which indexes are updated, and how documentation stays synchronized with code and user-visible behavior. Most projects should follow a structure like:

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

| Change Type | Document Location |
|---|---|
| New feature or module | `docs/features/{feature}.md` |
| Bug fix requiring durable documentation | `docs/bugs/{bug}.md` |
| API changes | `docs/api/{service-or-area}.md` |
| Domain model changes | `docs/features/domain-model.md` |
| Architecture decision | `docs/decisions/{NNN}-{title}.md` |
| UX specification | `docs/ux/{feature-or-flow}.md` |
| Deployment changes | `docs/infra/deployment.md` |
| Service Fabric topology | `docs/infra/service-fabric.md` |
| Server/network config | `docs/infra/` (appropriate file) |
| Security controls | `docs/infra/security.md` |
| Test strategy | `docs/features/{feature}-test-strategy.md` |

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

## Architecture Decision Record (ADR) guidance

Do not duplicate the ADR workflow here. Recommend the `architecture-decision-record` skill for ADR content, then use this skill to place the ADR under `docs/decisions/`, update indexes, and keep cross-references in sync.

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

Follow the applicable markdown style and project's existing documentation
conventions. Placement and ownership follow the canonical coordination policy,
not a competing local-precedence rule.

---

# Updating existing docs

When modifying an existing feature:

1. Find the relevant doc in `docs/`.
2. Update the affected sections to reflect the change.
3. If new sections are needed, add them following the existing structure.
4. Update any tables or reference data that changed.
5. Update the index (`docs/README.md`) if a new document was added.
6. Check if an existing ADR is affected — if so, recommend `architecture-decision-record` for superseding ADR content, then update indexes and cross-references.
7. Resolve remaining factual uncertainty from evidence; delegate only when justified.

---

# Creating a new feature doc

1. Create `docs/features/{feature}.md`.
2. Follow the standard document template above.
3. Use the approved requirements and acceptance criteria.
4. Verify technical details from the implementation or its existing evidence.
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
2. Verify pipeline/deployment details from the actual configuration and evidence.
3. Resolve integration/networking uncertainty before claiming operational readiness.
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
| `architecture-decision-record` | Recommend for ADR content. This skill owns ADR placement, index updates, and cross-reference sync. |
| `feature-planning` | Feature plans can be used as the basis for feature documentation. |
| `requirement-breakdown` | Requirement breakdowns inform what needs to be documented — each epic/story may need feature docs. |
| `test-strategy` | Recommend for deep test planning; this skill documents the resulting strategy in the right location. |
| `security-audit` | Recommend for deep security assessment; this skill documents resulting controls, threat models, and links. |

---

# Checklist for documentation changes

1. ☐ Relevant doc updated or created in `docs/`
2. ☐ Index (`docs/README.md`) updated if a new doc was added
3. ☐ Sub-folder index updated if a new doc was added
4. ☐ Writing style follows the applicable markdown-style instruction and existing docs conventions
5. ☐ Cross-references added where relevant (related docs, ADRs, API references)
6. ☐ All user-visible changes (UI, API, config) are documented
7. ☐ Domain facts verified from repository evidence or specialist input, with delegation proportional to the work
8. ☐ `architecture-decision-record` recommended or used if an architecture decision was involved
9. ☐ UX specification created if user-facing flows changed
10. ☐ API documentation updated if endpoints changed

---
