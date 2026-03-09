---
name: documentation
description: >
  Guides the creation and maintenance of project documentation in the docs/
  folder, ensuring consistency in structure, style, and coverage whenever
  functionality changes.
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

---

# When to use this skill

Use this skill whenever:

- You add, change, or remove functionality in the codebase.
- The user asks to document something.
- You create a new feature, endpoint, page, or entity.
- Infrastructure or deployment changes are made.

**Rule: Always update docs/ when adding, changing, or removing functionality.**

---

# Documentation structure

Most projects should follow a structure like:

```
docs/
├── README.md                    (main index with table of contents)
├── features/                    (feature documentation)
│   ├── README.md                (feature docs index)
│   └── {feature}.md
└── infrastructure/              (infrastructure/deployment docs)
    ├── README.md                (infrastructure docs index)
    └── {topic}.md
```

If the project already has a `docs/` folder, follow its existing structure. If not, create one following this pattern.

### Placement rules

| Change Type | Document Location |
|---|---|
| New feature or module | `docs/features/{feature}.md` |
| API changes | `docs/features/api-reference.md` |
| Domain model changes | `docs/features/domain-model.md` |
| Deployment changes | `docs/infrastructure/deployment.md` |
| Server/network config | `docs/infrastructure/` (appropriate file) |

---

# Document template

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

---

# Writing style

- **Audience**: Developers working on or deploying this project.
- **Voice**: Active, direct. "You can add an ingredient" not "Ingredients may be added".
- **Structure**: High-level overview first, then implementation specifics.
- **Step-by-step**: Use numbered lists for workflows and procedures.
- **Tables**: Use for structured reference data (fields, values, config settings).
- **Code blocks**: Include for configuration, commands, and technical details.
- **Cross-references**: Link between related docs.
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

---

# Creating a new feature doc

1. Create `docs/features/{feature}.md`.
2. Follow the document template above.
3. Include:
   - Overview of the feature and its purpose.
   - User workflows (browsing, creating, editing, deleting).
   - Input fields and requirements (tables).
   - API endpoints involved.
   - Domain entities and relationships.
   - Any special behaviour or edge cases.
4. Add an entry to `docs/features/README.md`.
5. Add an entry to `docs/README.md`.

---

# Creating a new infrastructure doc

1. Create `docs/infrastructure/{topic}.md`.
2. Include:
   - Purpose and context.
   - Scripts or tools involved (with usage examples).
   - Step-by-step procedures.
   - Environment variables and configuration (tables).
   - Network topology or architecture if relevant.
   - Troubleshooting tips.
3. Add an entry to `docs/infrastructure/README.md`.
4. Add an entry to `docs/README.md`.

---

# Checklist for documentation changes

1. ☐ Relevant doc updated or created in `docs/`
2. ☐ Index (`docs/README.md`) updated if a new doc was added
3. ☐ Sub-folder index updated if a new doc was added
4. ☐ Writing style matches existing docs (active voice, tables for data, code blocks)
5. ☐ Cross-references added where relevant
6. ☐ All user-visible changes (UI, API, config) are documented
