# Git Commit Review Redesign

## Status: Implemented

The Git review workflow now separates routine commit safety from deliberately exhaustive analysis.
This preserves high-signal review while avoiding repeated scans of unchanged code.

## Skill Selection

| Skill | Use when | Reviewers | Scope | Output |
|---|---|---|---|---|
| `git-commit-review` | Creating one normal, atomic commit | Exactly one `code-reviewer`; zero or one relevant specialist ordinarily, required expertise on escalation signals; a second specialist only for directly interacting high-risk domains | Staged index snapshot; targeted re-review only | One concise final commit report |
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
5. Reviews Critical and High findings within an approximately ten-minute timebox.
6. Stages approved fixes, records a new tree ID, rebuilds the snapshot, and repeats affected validation and targeted review only for changed files, prior finding locations, and directly affected contracts.
7. Requires explicit approval for every cycle after the second.
8. Runs the full existing test suite once at the final gate, with tracked-input
   integrity checks around validation commands.
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
Each specialist is a separately scoped `code-reviewer` assignment with relevant
on-demand domain notes. The three exhaustive hats likewise remain separate
reviewer assignments. Sharing a card does not remove required expertise,
independence, immutable intake or the read/search-only boundary.

### Reviewer-Count Examples

| Candidate | Core reviewers | Specialists |
|---|---:|---|
| Ordinary contained change, no escalation signal or distinct specialist need | 1 | 0 |
| Authentication change | 1 | 1: `code-reviewer` with security focus |
| Authorization directly interacting with a destructive migration | 1 | 2: separate security- and data-focused `code-reviewer` assignments |
| Large ordinary diff without an interacting high-risk pair | 1 | 0, or 1 when distinct relevant expertise is justified; never 2 for size alone |

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
| Always dispatched Architect, Principal Developer, and Senior Developer, plus up to three specialists | Dispatches exactly one `code-reviewer`; zero or one relevant specialist ordinarily, required domain expertise on escalation, and a second only for directly interacting high-risk domains |
| Could repeat a whole-diff review after every fix | Re-reviews only modified files, prior finding locations, and directly affected contracts |
| Created a full report for every cycle | Creates one concise final report, with a blocker record only when a Critical or High issue pauses work |
| Allowed three cycles before asking to continue | Requires explicit approval for each cycle after the second |
| Did not require a materialized index snapshot before review | Validates an index-only snapshot before any reviewer is launched |
| Used normal pre-commit review for deep analysis | Reserves the explicit `full-code-review` skill for exhaustive, multi-hat analysis |

## Finding Outcomes

Each concrete finding is classified as a commit blocker, accepted risk, delayed follow-up, or explicitly dropped finding.
Only unresolved Critical and High findings block the normal commit workflow.
