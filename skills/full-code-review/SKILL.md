---
name: full-code-review
description: >
  Explicitly invoked, exhaustive review of a diff, branch, or codebase area
  using three core review hats, up to three domain specialists, all severity
  levels, and a detailed persisted report.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

This is an analysis workflow, not a commit workflow.
After it completes, the user may explicitly invoke `git-commit-review` to create an atomic commit.

## When to use this skill

Use this skill only when the user explicitly requests exhaustive review.
Appropriate targets include:

- Release candidates.
- Major architectural changes.
- Security audits.
- Schema redesigns.
- Large, high-risk pull requests or branches.

Never run it automatically during normal pre-commit work or after `git-commit-review` escalation.
Do not use it as a replacement for splitting large changes into logical commits.

## 1. Define the review target

Confirm the exact target: a staged candidate, a branch range, a pull request diff, or named files.
For a large mixed diff, identify logical commit boundaries first and tell the user which scope each review covers.

### Freeze the evidence before checks or reviewers

The orchestrator prepares the input bundle; reviewers do not run Git or create
snapshots. Record repository identity, review mode, scope/exclusions, and:

| Target | Frozen identity and comparison |
|---|---|
| Staged candidate | Capture the index tree with `git write-tree`, the resolved base commit/tree (or explicit unborn/empty-tree base), and the base-to-index diff. Do not stage or include unstaged changes to prepare a review. |
| Branch/range or pull request | Resolve both endpoints to immutable commit/tree IDs; record the requested range semantics and merge-base ID if used. A branch name, PR number, or moving ref alone is not a review input. |
| Named files/codebase area | Capture the selected contents and directly required context in a path/type/content-hash manifest, including exclusions. Identify the source revision when available; mark base/diff not applicable for a file-only assessment. |

Materialize complete readable base/candidate context from those identities in
isolated temporary storage. Verify the manifest against the source objects or
captured files, not just the changed-path list; include required unchanged
configuration and dependencies. Detect omitted/transformed archive contents and
unresolved LFS/submodule/link inputs. If required inputs cannot be obtained or
frozen, stop with **Incomplete - missing evidence**, listing the missing inputs;
do not silently review the live worktree instead.

Keep that review bundle immutable. Run applicable repository-declared build,
type, import, and test commands in separate disposable validation copies rooted
in the same captured inputs. Record command, cwd, exit/result, and covered
identity. Compare all manifested paths/types/bytes before and after commands.
A manifested input mutation invalidates that run's evidence; restoring the
original bytes afterward cannot retroactively validate them. Ordinary untracked
build outputs are permitted but are not reviewer source inputs.

Report failed or unavailable checks as validation facts, not speculative code
findings or passing tests. Give all reviewers the same immutable identities,
diff, readable context, manifest, and validation evidence. Snapshot preparation
may use temporary storage; the report remains this workflow's only repository write.

## 2. Select reviewers

Always run these three independent, read-only core hats as separate
`code-reviewer` assignments, not as retired agent names:

| Hat | Focus |
|---|---|
| **Architect** | Structure, boundaries, dependencies, cross-cutting concerns, and shared-contract impact. |
| **Principal Developer** | Correctness, security, edge cases, error handling, performance, and maintainability. |
| **Senior Developer** | Functional completeness, repository conventions, tests, documentation, and long-term readability. |

Add up to three specialists when the scope warrants their distinct expertise:

| Domain | Specialist assignment |
|---|---|
| Authentication, authorization, secrets, cryptography | `code-reviewer`, security focus |
| Schema, migrations, queries, data integrity | `code-reviewer`, data/migration focus |
| CI/CD, deployment, containers, infrastructure | `code-reviewer`, infrastructure focus |
| Reliable Services, Actors, manifests, upgrades | `code-reviewer`, Service Fabric focus |
| UI, accessibility, responsive behavior, flows | `code-reviewer`, frontend/UX focus |
| APIs, middleware, contracts | `code-reviewer`, backend focus |
| Messaging, external systems, resilience | `code-reviewer`, integration focus |
| Test design and coverage | `code-reviewer`, tests focus |

Select specialists with non-overlapping scopes.
Each uses a separate reviewer assignment with the same immutable intake and
read/search-only boundary. Supply only relevant `skills/domain-guidance.md`
sections; required expertise does not disappear when role cards are shared.
Reviewers are read-only and must never concurrently edit the worktree, index, or review artifacts.
They return findings only; this workflow owns report consolidation and persistence.

## 3. Run the exhaustive review

Give every reviewer the same frozen review target and the scope assigned to its hat.
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
Only a separately authorized implementation step may change reviewed code; reviewers remain read-only, and report publication is the review workflow's only repository write.
Capture a new candidate and refresh the input bundle after fixes; repeat affected
validation/review and retain earlier evidence only for the identity it covers.

This skill does not create commits and does not invoke `git-commit-review`.

The initial exhaustive review is cycle one.
One targeted verification after fixes is cycle two.
Before starting cycle three or any later cycle, use `ask_user` to obtain explicit approval for that individual additional cycle.
The count never resets for the same review target.

## 6. Persist the detailed report

After consolidating the returned findings and their outcomes, write the full analysis to:

```text
.copilot/reports/reviews/{yyyy}/{MM}/full-review-{dd}-{hhmmss}.md
```

Include base/candidate identities or file-manifest identity, comparison semantics,
scope/exclusions, validation commands/cwds/results and evidence gaps, reviewer
scopes, all findings, deduplication notes, and the outcome for every finding.
Before publication, recheck the requested live target against the frozen identity.
If the branch, PR head, index, or selected files moved, retain the historical
findings but explicitly mark them as covering only the frozen target, not current
readiness. A new/changed candidate needs affected verification; drift or a new SHA
does not reset the cycle count for the same review objective.
If `/.copilot/` is not ignored, remind the user to add it to `.gitignore`.

## Relationship to `git-commit-review`

| Skill | Invocation and scope | Review depth | Commit behavior |
|---|---|---|---|
| `git-commit-review` | Default pre-commit workflow for one staged atomic candidate | Exactly one core reviewer; zero or one relevant specialist ordinarily, required domain expertise on escalation signals, and a second specialist only for directly interacting high-risk domains; Critical and High focus | Requires user verification and approved message, then creates the commit |
| `full-code-review` | Explicit user request for a release candidate, major redesign, security audit, schema redesign, or exhaustive analysis | Three core hats, up to three specialists, all severities, whole-target analysis | Does not create a commit |

`git-commit-review` never invokes this skill automatically.
