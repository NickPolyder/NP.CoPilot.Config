# repo-bootstrap templates

Source templates used by the [`repo-bootstrap`](../../skills/repo-bootstrap/SKILL.md)
skill to give a target repository the same **agent operating manual + durable
file-based working memory** structure that makes agent-driven repos effective.

`{{PLACEHOLDER}}` tokens are filled in by the skill (interview answers + repo
analysis). The skill never copies these verbatim — it tailors the content to the
target repo.

Use the whole configuration repository (including this sibling template tree).
Distributing only the `skills/repo-bootstrap` directory is not supported unless
a compatible source/asset root is explicitly supplied and verified.
Missing templates are an explicit preflight blocker, not permission to invent
successful output or fetch/vendor an unrelated copy.

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

## One delivery-capability owner

Fill `{{DELIVERY_CAPABILITIES_SECTION}}` using one of these contracts:

- If `.github/instructions/project-config.instructions.md` already declares
  capabilities, preserve/update that section using verified repository evidence.
  Put `<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->`
  in both files, and put only a link to
  `[project-config](instructions/project-config.instructions.md)`
  in the root contract's capability section. Do not add a second table.
- Otherwise the root contract owns the verified capability table. Put
  `<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`
  in its section. Its table has `Capability`, `Enabled`, and
  `Repository-specific rule` columns and covers issue tracking, isolated
  worktrees, remote delivery, protected branches, integration queue, and
  deployment evidence. Disabled/blank entries impose no additional requirement.

The project installer recognizes these markers and legacy capability tables.
It preserves an existing project-config capability section even during Force or
template refresh. If only the root contract owns capabilities, it emits a
root-owner marker and reference instead of a second default-disabled table.
Conflicting owners or a reference to a missing declaration require explicit
reconciliation; Force does not resolve them by resetting capabilities.

Root `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` may already own capability facts.
The installer detects their tables or unmarked delivery-capability sections and
stops before emitting competing defaults. Resolve an explicit preservation/
reference or migration plan with `repo-bootstrap` first; do not invent a third
owner marker or silently move the declaration. Existing references from those
contracts to a valid two-path owner are supported and left untouched. Malformed
owner markers or a missing referenced declaration also stop installation.

## Continuity and plugin boundaries

Tailor `HANDOVER_OWNER` and `HANDOVER_MECHANISM` to the repository's declared
owner and capabilities actually available in the target session. Existing
project/cross-agent records remain authoritative and must stay accurate.
With `np-agent-memory` owning continuity, no unsolicited duplicate Markdown
session export is required. Do not infer active discovery or registration from
an imported instruction's external provenance, a symlink, or a retained backup.
Report missing capabilities (including unsupported/non-Git contexts) without
claiming persistence, vendoring the plugin, or modifying an external home.
