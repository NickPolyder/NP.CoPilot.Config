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

Project delivery facts override global defaults. Complete only capabilities supported by repository evidence.

| Capability | Enabled | Repository-specific rule |
|---|---:|---|
| Issue tracking | {{ISSUE_TRACKING_ENABLED}} | {{ISSUE_TRACKING_RULE}} |
| Isolated worktrees | {{ISOLATED_WORKTREES_ENABLED}} | {{ISOLATED_WORKTREES_RULE}} |
| Remote delivery | {{REMOTE_DELIVERY_ENABLED}} | {{REMOTE_DELIVERY_RULE}} |
| Protected branches | {{PROTECTED_BRANCHES_ENABLED}} | {{PROTECTED_BRANCHES_RULE}} |
| Integration queue | {{INTEGRATION_QUEUE_ENABLED}} | {{INTEGRATION_QUEUE_RULE}} |
| Deployment evidence | {{DEPLOYMENT_EVIDENCE_ENABLED}} | {{DEPLOYMENT_EVIDENCE_RULE}} |

Follow the global work lifecycle and delivery policies; this table declares only repository-specific capabilities and evidence.

## Commits

- Conventional Commits, imperative mood.
- Include the `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
  trailer.
- {{COMMIT_GROUPING_CONVENTION — e.g. "Group commits by phase: feat(phase-N): ..."}}

## Session handover

When you wrap substantial work in this repo:

- Update [`docs/TASKS.md`](../docs/TASKS.md) status so the next session sees
  current progress.
- {{HANDOVER_MECHANISM — e.g. "Write a handover in docs/handoffs/" or "use the
  agent-memory handover_save tool".}}

## Don't

> Explicit guardrails. These are the mistakes most likely to happen here.

- {{DONT_1}}
- {{DONT_2}}
- {{DONT_3}}
- Don't break out of the phased plan without writing a short ADR in
  `docs/decisions/` explaining why.
- Don't commit secrets, credentials, or sensitive data.
