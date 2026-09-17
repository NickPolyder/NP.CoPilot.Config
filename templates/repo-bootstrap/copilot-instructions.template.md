# Custom Instructions — {{REPO_NAME}}

> This file is the **repo-level agent operating manual**. It extends the global
> Copilot configuration in `~/.copilot/` — it never contradicts it. Keep it
> tight: rules an agent must follow, not a project README.

{{ONE_LINE_REPO_SUMMARY}}

## Repository mission

{{REPOSITORY_MISSION — the user, domain outcome, and non-negotiable constraints for this repository}}

## Agent role in this repo

You are the **{{PRIMARY_AGENT_ROLE}}**. Your job is to {{PRIMARY_OBJECTIVE}},
working from [`docs/PLAN.md`](../docs/PLAN.md) (the canonical design) and
[`docs/TASKS.md`](../docs/TASKS.md) (the phased, ordered execution plan).

- Treat `docs/PLAN.md` and `docs/TASKS.md` as the **source of truth**. If the
  code and the plan disagree, reconcile them deliberately — don't silently drift.
- Record non-obvious choices as ADRs in [`docs/decisions/`](../docs/decisions/).
- {{OTHER_AGENTS_NOTE — e.g. "The X agent owns Y and does not implement this repo."}}

## Hard rules

> Non-negotiable constraints. Violating one of these is a defect, not a judgment
> call. Keep this list short and specific — 4–8 rules that actually matter here.

- {{HARD_RULE_1}}
- {{HARD_RULE_2}}
- {{HARD_RULE_3}}
- {{HARD_RULE_4}}

## Style

- **Code style:** follow the conventions in the user-level instructions at
  `~/.copilot/instructions/` (auto-loaded). {{LANGUAGE_SPECIFIC_STYLE_NOTES}}
- **{{SECONDARY_LANGUAGE}} style:** {{SECONDARY_STYLE_NOTES}}
- **Tests travel with their code** — they belong in the same commit as the
  change they cover.

## Build, test, lint

> Verified commands only. An agent should be able to copy-paste these.

```
restore: {{RESTORE_CMD}}
build:   {{BUILD_CMD}}
test:    {{TEST_CMD}}
lint:    {{LINT_CMD}}
```

## Delivery capabilities

{{DELIVERY_CAPABILITIES_SECTION}}

Follow the global work lifecycle and delivery policies. Keep one capability
owner: preserve/update an existing project-config declaration and reference it
here; otherwise this contract owns the verified declaration. Never repeat a
second default-disabled table over an existing owner's verified values.

## Commits

- Conventional Commits, imperative mood.
- Include the `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
  trailer.
- {{COMMIT_GROUPING_CONVENTION — e.g. "Group commits by phase: feat(phase-N): ..."}}

## Session handover

When you wrap substantial work in this repo:

- Update [`docs/TASKS.md`](../docs/TASKS.md) status so the next session sees
  current progress.
- **Session-continuity owner:** {{HANDOVER_OWNER — the repository's declared
  mechanism or plugin, for example np-agent-memory.}}
- {{HANDOVER_MECHANISM — use the declared owner's available tools; verify
  registration and report a blocker if required capabilities are unavailable.}}
- Maintain existing required project/cross-agent records truthfully, including
  blockers and delivery state. These are not duplicate session exports.
- When `np-agent-memory` owns session continuity, use it without creating an
  unsolicited parallel Markdown handover. Create a new Markdown handoff only
  when requested or required for a concrete project/cross-agent exchange.
- Imported plugin instructions or retained backups do not prove that the
  plugin's tools are registered or its instructions are active. Preserve the
  declared owner and report unavailable capabilities; do not vendor the plugin,
  modify another home, or silently switch persistence mechanisms.

## Don't

> Explicit guardrails. These are the mistakes most likely to happen here.

- {{DONT_1}}
- {{DONT_2}}
- {{DONT_3}}
- Don't break out of the phased plan without writing a short ADR in
  `docs/decisions/` explaining why.
- Don't commit secrets, credentials, or sensitive data.
