# repo-bootstrap templates

Source templates used by the [`repo-bootstrap`](../../skills/repo-bootstrap/SKILL.md)
skill to give a target repository the same **agent operating manual + durable
file-based working memory** structure that makes agent-driven repos effective.

`{{PLACEHOLDER}}` tokens are filled in by the skill (interview answers + repo
analysis). The skill never copies these verbatim — it tailors the content to the
target repo.

## Layout

```
copilot-instructions.template.md   → target: .github/copilot-instructions.md  (the contract)
docs/PLAN.md                       → target: docs/PLAN.md     (canonical design)
docs/TASKS.md                      → target: docs/TASKS.md    (phased execution)
docs/decisions/0000-template.md    → target: docs/decisions/0000-template.md  (ADR template)
docs/decisions/README.md           → target: docs/decisions/README.md         (ADR index)
docs/features/README.md            → target: docs/features/README.md
docs/handoffs/README.md            → target: docs/handoffs/README.md
docs/reviews/README.md             → target: docs/reviews/README.md
docs/retrospectives/README.md      → target: docs/retrospectives/README.md
```

## Relationship to other scaffolding

- **`install-project.ps1`** drops `project-config` + `local-preferences` into
  `.github/instructions/` (tech-stack facts). `repo-bootstrap` complements it
  with the agent contract + docs memory tree.
- **ADRs, features, retros** are seeded here as templates/indexes only — the
  detailed content is produced by the `architecture-decision-record`,
  `feature-planning`/`prd-workflow`, and `retrospective` skills.
