---
name: full-code-review
description: >
  Explicitly invoked, exhaustive review of a diff, branch, or codebase area
  using three core review hats, up to three domain specialists, all severity
  levels, and a detailed persisted report.
tags:
  - code-review
  - workflow
  - quality
visibility: user
tools:
  [agent, code-review, edit/editFiles, todo]
---

# Purpose

> **Intent (anchor):** Perform an exhaustive, multi-reviewer analysis only when the user explicitly requests it.
> **Always:** define the review scope; use three distinct core review hats; include all severity levels; produce a detailed report.
> **Never:** run automatically during normal pre-commit work; invoke or nest another orchestrator; edit the reviewed worktree; create a commit.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

This is an analysis workflow, not a commit workflow.
After it completes, the user may explicitly invoke `git-commit-review` to create an atomic commit.

## When to use this skill

Use this skill only when the user explicitly asks for exhaustive review, or for:

- Release candidates.
- Major architectural changes.
- Security audits.
- Schema redesigns.
- Large, high-risk pull requests or branches.

Do not use it automatically after `git-commit-review` escalation.
Do not use it as a replacement for splitting large changes into logical commits.

## 1. Define the review target

Confirm the exact target: a staged candidate, a branch range, a pull request diff, or named files.
For a large mixed diff, identify logical commit boundaries first and tell the user which scope each review covers.

Run directly applicable build, type, import, and test checks before reviewers so failures are reported as facts rather than speculation.
Record validation failures in the report and do not disguise them as reviewer findings.

## 2. Select reviewers

Always run these three independent, read-only core hats:

| Hat | Focus |
|---|---|
| **Architect** | Structure, boundaries, dependencies, cross-cutting concerns, and shared-contract impact. |
| **Principal Developer** | Correctness, security, edge cases, error handling, performance, and maintainability. |
| **Senior Developer** | Functional completeness, repository conventions, tests, documentation, and long-term readability. |

Add up to three specialists when the scope warrants their distinct expertise:

| Domain | Specialist |
|---|---|
| Authentication, authorization, secrets, cryptography | `security-engineer` |
| Schema, migrations, queries, data integrity | `database-engineer` |
| CI/CD, deployment, containers, infrastructure | `devops-engineer` |
| Reliable Services, Actors, manifests, upgrades | `service-fabric-engineer` |
| UI, accessibility, responsive behavior, flows | `frontend-developer` or `ux-engineer` |
| APIs, middleware, contracts | `backend-developer` |
| Messaging, external systems, resilience | `systems-engineer` |
| Test design and coverage | `qa-engineer` |

Select specialists with non-overlapping scopes.
Reviewers are read-only and must never concurrently edit the worktree, index, or review artifacts.

## 3. Run the exhaustive review

Give every reviewer the same defined review target and the scope assigned to its hat.
Review the whole target, its directly affected contracts, and relevant surrounding code where that context is necessary.

Every finding must include:

- Severity: Critical, High, Medium, or Low.
- Exact file and line references.
- The impact and rationale.
- A concrete remediation or explicitly stated uncertainty.

Do not manufacture findings to fill a role.
Deduplicate findings and retain all material severity levels in the consolidated report.

## 4. Consolidate and classify

Organize deduplicated findings by severity and record one of these outcomes for each:

| Outcome | Meaning |
|---|---|
| **Commit or merge blocker** | Critical or High issue requiring resolution before the user proceeds. |
| **Accepted risk** | User explicitly accepts a documented risk. |
| **Delayed follow-up** | Valuable issue scheduled for later work. |
| **Explicitly dropped** | Finding rejected with documented rationale. |

Medium and Low findings are visible and actionable, but they do not block unless the user or repository policy elevates them.

## 5. Optional fix verification

If the user requests fixes, confine re-review to modified files, previous finding locations, and directly affected contracts unless the user requests another whole-target pass.
Run affected direct checks after each fix.

This skill does not create commits and does not invoke `git-commit-review`.

## 6. Persist the detailed report

Write the full consolidated analysis to:

```text
.copilot/reports/reviews/{yyyy}/{MM}/full-review-{dd}-{hhmmss}.md
```

Include review target, validation results, reviewer scopes, all findings, deduplication notes, and the outcome selected for every finding.
If `/.copilot/` is not ignored, remind the user to add it to `.gitignore`.

## Relationship to `git-commit-review`

| Skill | Invocation and scope | Review depth | Commit behavior |
|---|---|---|---|
| `git-commit-review` | Default pre-commit workflow for one staged atomic candidate | One core reviewer, one specialist by default, and a second only for high-risk cross-domain work; Critical and High focus | Requires user verification and approved message, then creates the commit |
| `full-code-review` | Explicit user request for a release candidate, major redesign, security audit, schema redesign, or exhaustive analysis | Three core hats, up to three specialists, all severities, whole-target analysis | Does not create a commit |

`git-commit-review` never invokes this skill automatically.

## Final Rules (Anchor)

1. Run only on explicit user invocation; never run automatically during normal pre-commit work.
2. Use Architect, Principal Developer, and Senior Developer hats plus no more than three relevant specialists.
3. Keep all reviewers read-only and never allow concurrent edits to the worktree.
4. Include all severity levels and persist a detailed report.
5. Do not create commits or invoke `git-commit-review`.
