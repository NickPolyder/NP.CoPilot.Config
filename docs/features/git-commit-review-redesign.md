# Git Commit Review Redesign

## Status: Implemented

The Git review workflow now separates routine commit safety from deliberately exhaustive analysis.
This preserves high-signal review while avoiding repeated scans of unchanged code.

## Skill Selection

| Skill | Use when | Reviewers | Scope | Output |
|---|---|---|---|---|
| `git-commit-review` | Creating one normal, atomic commit | One `code-reviewer`, one relevant specialist, and a second only for high-risk cross-domain changes | Staged index snapshot; targeted re-review only | One concise final commit report |
| `full-code-review` | Explicitly requested release candidate, major architecture change, security audit, schema redesign, or exhaustive analysis | Architect, Principal Developer, Senior Developer, and up to three specialists | Whole requested diff or code area | Detailed review report |

`full-code-review` is never automatically invoked by `git-commit-review`.

## Lightweight Workflow

`git-commit-review` now:

1. Splits mixed work into atomic candidates and stages one candidate only.
2. Materializes the Git index in a temporary clean snapshot.
3. Runs import, build, type, and targeted test checks against that snapshot before reviewers start.
4. Stops immediately when preflight fails.
5. Reviews Critical and High findings within an approximately ten-minute timebox.
6. Re-reviews only changed files, prior finding locations, and directly affected contracts after a fix.
7. Requires explicit approval for every cycle after the second.
8. Runs the full existing test suite once at the final gate.
9. Requires manual verification and approved conventional commit message before committing.

## Automatic Escalation

The lightweight workflow automatically adds the relevant specialist for the following staged changes:

| Trigger | Specialist |
|---|---|
| Authentication, authorization, cryptography, or secrets | Security |
| Destructive or irreversible database migration | Database |
| External production write | Systems Integration |
| Broad-blast-radius deployment or infrastructure change | DevOps |
| Safety-critical concurrency or data-integrity change | Systems Integration or Database |

Escalation adds expertise without promoting the review to `full-code-review`.

## Migration Notes

| Previous behavior | New behavior |
|---|---|
| Always dispatched Architect, Principal Developer, and Senior Developer, plus up to three specialists | Dispatches one `code-reviewer` and at most one relevant specialist; a second specialist requires high-risk cross-domain work |
| Could repeat a whole-diff review after every fix | Re-reviews only modified files, prior finding locations, and directly affected contracts |
| Created a full report for every cycle | Creates one concise final report, with a blocker record only when a Critical or High issue pauses work |
| Allowed three cycles before asking to continue | Requires explicit approval for each cycle after the second |
| Did not require a materialized index snapshot before review | Validates an index-only snapshot before any reviewer is launched |
| Used normal pre-commit review for deep analysis | Reserves the explicit `full-code-review` skill for exhaustive, multi-hat analysis |

## Finding Outcomes

Each concrete finding is classified as a commit blocker, accepted risk, delayed follow-up, or explicitly dropped finding.
Only unresolved Critical and High findings block the normal commit workflow.
