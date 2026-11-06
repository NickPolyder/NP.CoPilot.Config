# Git Commit Review Redesign

## Status: Implemented

**Updated:** 2026-11-06.

The Git review workflow now separates routine commit safety from deliberately exhaustive analysis.
This preserves high-signal review while avoiding repeated scans of unchanged code.

## Skill Selection

| Skill | Use when | Reviewers | Scope | Output |
|---|---|---|---|---|
| `git-commit-review` | Creating one normal, atomic commit | One focused `code-reviewer`; separate specialists only when repository-required or user-requested | Staged index snapshot; one shared ten-minute review budget including targeted fix verification | One compact outcome and one candidate/message approval |
| `full-code-review` | Explicitly requested release candidate, major architecture change, security audit, schema redesign, or exhaustive analysis | Architect, Principal Developer, Senior Developer, and up to three specialists | Whole requested diff or code area, frozen to immutable identities or a file manifest | Detailed review report |

`full-code-review` is never automatically invoked by `git-commit-review`.

## Lightweight Workflow

`git-commit-review` now:

1. Splits mixed work into atomic candidates and stages one candidate only.
2. Captures the candidate tree, base, ordered parents, ref state, and destination;
   materializes a temporary clean snapshot and verifies complete tree contents
   separately from changed-path review scope.
3. Runs import, build, type, and targeted test checks against that snapshot before reviewers start.
4. Stops immediately when preflight fails.
5. Gives one focused reviewer a shared ten-minute budget for initial review,
   findings consolidation, and any targeted verification of blocker fixes.
   The caller records elapsed review time; extra reviewers and fixes do not
   reset the allowance. Required checks, implementation, and approval waits
   are timed separately.
6. Stops when the assigned scope is covered, including a clean first review.
   Only concrete, reachable Critical or High defects introduced or worsened by
   the candidate block; incidental minor findings do not trigger fix cycles.
7. After an authorized blocker fix, captures fresh staged inputs and checks only
   affected behavior, prior findings, and directly affected contracts.
   No broad rescan or phase-only rerun is required.
8. Runs full suites only when required by repository policy or affected behavior;
   reuses still-valid checks instead of automatically repeating final validation.
9. Requires manual verification and approval of the conventional commit message
   plus the exact candidate/base/parent/ref tuple before committing.
10. Rechecks that tuple and snapshot integrity immediately before commit, then
    verifies the resulting tree, ordered parents, and destination/ref state.
    A mismatch stops delivery; these checks are not a lock against concurrent writers.

### Snapshot Identity Correction (2026-09-15)

An index tree contains all tracked files, including unchanged files.
The staged diff describes only changes and can include deletions that are absent from the tree.
These file sets must not be compared for equality.
The [skill](../../skills/git-commit-review/SKILL.md) now checks snapshot contents against the captured tree, and uses the diff only to scope review.
Archive attributes, checkout filters, submodules, and LFS must not silently remove or transform required validation inputs.

Each restaged fix invalidates the old snapshot for affected checks.
The final report records the validated tree ID so validation, review, and the resulting commit can be traced to the same candidate.
The review-policy validator checks selected wording for these requirements; it does not establish that a session executed them correctly.

### Executable Candidate Contract (2026-09-16)

The operational [skill](../../skills/git-commit-review/SKILL.md) now specifies the
configuration source repository's `scripts\GitSnapshot.psm1` helpers for raw-tree
materialization and exact-candidate checks. The whole-repository asset dependency
is explicit; a missing helper is not permission to use a lossy archive fallback.
Its supported filesystem/type boundaries and executable regression evidence
belong to the helper/validation owner.

Base or destination drift invalidates approval even if the staged tree is
unchanged. Tracked snapshot mutation invalidates validation even if the command
exits zero; restoring bytes later cannot retroactively make that run valid.
Ordinary untracked build outputs do not by themselves invalidate captured inputs.
The caller retains these identities and results when supplying the reviewer's
immutable intake bundle. This summary describes the required procedure, not a
claim that every running agent or concurrent Git operation is controlled by it.

## Focus and Stopping

Domain risk changes the core reviewer's focus, not the default reviewer count.
The commit workflow does not audit unchanged subsystems or search for optional
architecture, coverage, dependency, documentation, or style improvements.
Additional independent reviewers need a repository requirement or user request,
non-overlapping scopes, and the same remaining review budget.

At budget exhaustion, stop further review and report
**Paused - review budget exhausted**, known findings, remaining scope, and gates.
Ask whether to split the candidate or authorize a specific additional budget.
Do not silently extend the review, replace reviewers, mark incomplete coverage
clean, or commit automatically. A tool overrun must be disclosed.
Permission for a third or later cycle does not itself grant more time.
Required independent review is never waived to fit the budget.

### Reviewer-Count Examples

| Candidate | Core reviewers | Specialists |
|---|---:|---|
| Ordinary contained change | 1 | 0 |
| Authentication change | 1, with security focus | 0 unless independently required or requested |
| Repository mandates independent migration review | 1 | Required separate data-focused assignment, within the shared budget |
| Large ordinary diff | 1 | 0 by default; propose splitting if it cannot fit the budget |

The [read/search-only reviewer](../../agents/code-reviewer.md#required-intake)
requires caller-supplied base/candidate identities, the complete diff, immutable
readable context, and available validation evidence. It can return a bounded
review to an active workflow without restarting that workflow or creating files.
A branch-name-only request returns missing evidence, not a substituted current-file
review. The operational commit skill owns preparation and approval mechanics.

Exhaustive review separately freezes staged/range/file targets, records
commands/cwds and manifest integrity, and reports target drift rather than
extending old findings to a moving branch. These are evidence contracts, not
proof that an autonomous session executed every step.

## Migration Notes

| Previous behavior | New behavior |
|---|---|
| Always dispatched multiple hats or keyword-triggered specialists | Dispatches one focused `code-reviewer`; separate reviewers only when repository-required or user-requested |
| Could repeat a whole-diff review after every fix | Re-reviews only modified files, prior finding locations, and directly affected contracts |
| Created a full report for every cycle | Creates one concise final report, with a blocker record only when a Critical or High issue pauses work |
| Treated each pass or reviewer as another time allowance | Shares ten minutes across initial review, consolidation, and targeted fix verification; pauses incomplete coverage rather than extending silently |
| Did not require a materialized index snapshot before review | Validates an index-only snapshot before any reviewer is launched |
| Used normal pre-commit review for deep analysis | Reserves the explicit `full-code-review` skill for exhaustive, multi-hat analysis |

## Finding Outcomes

Each concrete finding is classified as a commit blocker, accepted risk, delayed follow-up, or explicitly dropped finding.
Only unresolved Critical and High findings block the normal commit workflow.
