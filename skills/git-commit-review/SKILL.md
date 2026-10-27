---
name: git-commit-review
description: >
  Lightweight pre-commit workflow that splits atomic candidates, validates an
  index-only snapshot, runs direct checks, and performs a targeted review before
  creating a safe, approved commit.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs; `instructions/workflow.instructions.md` for proportional verification; and `instructions/git-conventions.instructions.md` for delivery and commit safety.

This is the default pre-commit workflow.
It is intentionally bounded to approximately ten minutes of reviewer time.

Use `full-code-review` only when the user explicitly requests exhaustive analysis.
Recommendations for `full-code-review` or `security-audit` are separate handoffs after this owning workflow ends, never nested invocations.
Never mark a blocked workflow complete merely to start another workflow.

## When to use this skill

Use this skill when a logical change is ready to commit.
Do not start it merely because implementation finished; commit creation must be
within the user's requested scope.

Do not use it for:

- A user-requested full review, release candidate, major architectural change, security audit, or schema redesign; recommend `full-code-review`.
- A trivial change when the user explicitly chooses to skip review.
- An empty index.

## Commit purpose and pending validation

Use the normal reviewed-commit path by default. An explicitly requested
**checkpoint commit** uses the same snapshot, local-check, review and approval
gates; it only permits identified post-commit/live checks to remain pending.
Do not ask users to select a mode for ordinary commits.

Before using this exception:

- Establish why each deferred check needs a committed revision or live
  environment, and confirm repository policy permits deferral at the commit
  boundary. Required pre-commit checks cannot be deferred.
- Record each check as **Pending - post-commit/live validation**, with its
  command/procedure, reason, target environment, responsible owner, trigger and
  the merge/release/acceptance gate it must satisfy. Bind the follow-up to the
  resulting commit SHA; changed content needs refreshed evidence.
- Never defer failed checks on the current candidate or missing required local
  commands/inputs. Failures from earlier revisions remain recorded; a changed
  fix may need a pending live retest. Do not claim resolution until it passes.
- If another workflow owns the work, return to its owner. Only explicit
  user-directed suspension of the owner and any parent permits this separate
  checkpoint workflow; preserve unfinished tasks and resume conditions.
  The checkpoint request supplies the suspension direction; do not ask twice.

Checkpoint approval never authorizes push or deployment. Merge, release and
completion still require their own evidence and repository controls. Do not
infer that a test branch is safe: a push may itself trigger deployment.

## 1. Split atomic candidates and stage one

Inspect the worktree and divide it into logical, atomic commit candidates before adding reviewers.

- Keep one feature, fix, refactor, configuration change, or documentation concern in each candidate.
- Keep tests with the behavior they cover.
- Do not compensate for a large mixed diff by adding reviewers.
- Stage exactly one candidate with partial staging where necessary.
- Confirm the index contains no unrelated files or hunks.

Preserve unrelated staged and unstaged work; do not reset or restage it to
simplify the candidate. Ask before changing an index arrangement that cannot
safely isolate the authorized hunks.

If a candidate is not self-contained, split it before continuing.
Do not review unstaged changes or a mixture of candidates.

## 2. Materialize the clean index snapshot

Review the index, not the mutable worktree.

1. Require a non-empty index diff against the recorded base: HEAD, or the empty tree for an unborn branch.
2. Resolve `$snapshotHelper` to `scripts\GitSnapshot.psm1` in **this configuration's source repository**, not the target project. The whole-repository installation provides it; do not assume a standalone copied skill includes it. If unavailable, stop and report the missing capability rather than inventing an archive fallback.
3. Run the shared executable procedure below with `$repositoryRoot` identifying the target worktree root. `New-GitReviewCandidate` uses `git write-tree` only on a disposable index copy; it records the exact candidate tree, base identity, ordered parent list, unborn/detached/symbolic ref state, and destination ref. The snapshot and isolated child home are outside the target repository.

<!-- tested-snapshot:start -->
```powershell
Import-Module $snapshotHelper -ErrorAction Stop
$candidate = New-GitReviewCandidate -RepositoryRoot $repositoryRoot
$snapshot = New-GitTreeSnapshot -Candidate $candidate
$baseSnapshot = New-GitTreeSnapshot -Candidate $candidate -Base
Assert-GitSnapshotIntegrity -Snapshot $snapshot -Exact
Assert-GitSnapshotIntegrity -Snapshot $baseSnapshot -Exact
Assert-GitCandidateCurrent -Candidate $candidate
```
<!-- tested-snapshot:end -->

4. Verify snapshot paths, file types, modes, and bytes against the captured tree with the helper's `git ls-tree -r -z --full-tree` manifest and raw `git cat-file blob` output. It includes unchanged tracked files, excludes deletions, and ignores archive/checkout transformations (`export-ignore`, `export-subst`, smudge filters, EOL conversion, and ident substitution). It never uses archive success as proof of completeness. Its initial `-Exact` gate rejects extra paths as well as missing or altered inputs.
5. Use changed paths only for review scope, not snapshot completeness. `$candidate.DiffBytes` is the binary-capable base-to-tree diff; `$candidate.ChangedPaths` comes from NUL-delimited, rename-disabled discovery so both rename sides, deletions, and type changes are in scope. `Assert-GitCandidateCurrent` rechecks the full tuple, not just the index tree, before accepting these as one candidate.
6. Follow the raw-tree/filesystem contract in `scripts\README.md`. Unsupported inputs fail closed by default; prefer POSIX for Git mode 100755. For a platform/filesystem fidelity limitation, section 6 permits a candidate-specific exception using an identified helper override or snapshot procedure. Disclose affected paths/modes, bypass, lost guarantees, remaining checks, and risks before obtaining explicit user acceptance. Carry the exception through later gates, reviewer intake, final approval, and the outcome; report the waived guarantee as **Accepted exception**, never passed. Preserve immutable tree bytes, candidate identity, required checks, and delivery controls. No worktree substitution, silent checkout transformations, or unrelated bypasses. Stop if the remaining guarantees cannot be preserved; approval alone does not enable an unsupported helper.
7. `$baseSnapshot` supplies readable context at the captured base tree, including deleted files and old rename paths; an unborn base has an empty manifest. Both snapshots expose `Tree`, `Role`, `Path`, and `Manifest` (paths, modes, and blob IDs). Base context is read-only review evidence, never a substitute validation target.
8. Keep the candidate and both snapshots for all checks and review. In a `finally` block at workflow termination, call `Remove-GitReviewCandidate -Candidate $candidate` to remove only its owned snapshots, index copies, and isolated child state.

Never substitute the working tree for this snapshot.
Unstaged changes must not affect validation or reviewer conclusions.

## 3. Direct validation preflight

Before dispatching a reviewer, establish the applicable local validation
evidence against the index-only snapshot. Run missing or invalidated checks;
reuse evidence only under the rules below. An approved checkpoint's explicitly
pending live checks are coverage limits, not failed local preflight.

- Derive commands from repository documentation and manifests; do not invent a new toolchain.
- Prefer the narrowest checks that exercise the staged behavior.
- Documentation-only candidates need applicable documentation/configuration
  checks, not unrelated builds. Review consequential policy, command and
  contract changes even when their files are Markdown.
- Run imports or compilation before tests so direct failures are surfaced first.
- Run the commands from the snapshot or point them at snapshot paths, never at the working tree.
- Discover repository-declared validation capabilities from the captured documentation and manifests. The presence of Copilot configuration alone does **not** imply that the target has `scripts\Validate-Config.ps1`. Do not require another project to copy this repository's validator.
- **For NP.CoPilot.Config**, the declared required configuration check remains `pwsh -NoProfile -File .\scripts\Validate-Config.ps1 -RepositoryRoot <snapshot-path>`, executed in the snapshot. Run its focused regression suite when the validator or its tests change. In any project, a declared required command or input that is missing must fail explicitly; never fall back to the mutable worktree.
- Run each potentially writing preflight, restore, build, lint, or test command through `Invoke-GitSnapshotCheck`, with its executable, argument array, name, and snapshot-relative `-RequiredPaths` (if any). It checks tracked input integrity and candidate identity before and after the command, and checks the native exit code. Ordinary untracked files/directories produced by builds are allowed after materialization; linked outputs are not.
- Before reviewer dispatch, call `Assert-GitSnapshotIntegrity -Snapshot $snapshot`, `Assert-GitSnapshotIntegrity -Snapshot $baseSnapshot -Exact`, and `Assert-GitCandidateCurrent -Candidate $candidate` again. Tracked input mutation invalidates the snapshot's evidence even if the command exits zero. Do not run checks against mutated inputs and then restore bytes to claim evidence for the originals. An observed failure is latched: restoring bytes does not clear it. Restage intended fixes, rematerialize, and rerun affected checks on the new candidate; do not hide mutation with cleanup inside a validation command.

If the snapshot cannot be materialized, imports/build/type checks fail, or targeted tests fail, stop.
Report the concrete failure and fix it before launching any reviewer.
One proven clean-index failure is more valuable than speculative reviewer feedback.

### Reusing validation evidence

Reuse only successful snapshot-backed evidence for the same full candidate
tuple, tracked input manifests, command/arguments, working-directory semantics,
toolchain, dependencies, relevant environment and required freshness. Keep the
original result and integrity gates readable; record **Reused - passed**, its
source and coverage, rather than claiming another execution. If any dependency
or freshness cannot be established, rerun the affected check.

Worktree-only results, tree equality without the full tuple, and restored bytes
after invalidation are not reusable evidence. Reuse does not skip current
snapshot/candidate integrity gates, satisfy a requirement for a fresh run, or
prove missing build outputs exist in a new snapshot.

## 4. Select reviewers and escalate risk

Start with exactly one core reviewer: `code-reviewer`.
Select at most one relevant specialist in ordinary review (zero or one); signal-driven expertise is required when a risk signal applies.

| Staged-change signal | Specialist assignment |
|---|---|
| Authentication, authorization, cryptography, secrets | `code-reviewer`, security focus |
| Destructive or irreversible database migration; safety-critical data integrity | `code-reviewer`, data/migration focus |
| External production writes; integration-side data integrity | `code-reviewer`, integration focus |
| Deployment or infrastructure change with broad blast radius | `code-reviewer`, infrastructure focus |
| Safety-critical concurrency | `code-reviewer`, concurrency and affected-domain focus |

These signals automatically add the appropriate specialist; they never invoke `full-code-review`.
Each specialist uses a separate `code-reviewer` assignment with a domain focus and the same immutable intake and read/search-only boundary.
Supply only the relevant sections of `skills/domain-guidance.md`. Sharing a role
card does not merge the core and specialist scopes or waive required expertise.

Add a second specialist only when two distinct high-risk domains directly interact in the same candidate, such as authorization plus destructive migration or production writes plus broad deployment changes.
Do not add a second specialist merely because a large diff touches multiple ordinary domains.

Assign non-overlapping scopes before dispatch:

- `code-reviewer` covers correctness, changed contracts, and high-signal repository-pattern violations.
- Each specialist covers only its triggered domain.

Reviewers are read-only.
Concurrent reviewers must never edit the worktree, the index, or the snapshot.

## 5. Run the targeted review

Run the core reviewer and selected specialists against the materialized snapshot and staged diff.
Timebox the review stage to approximately ten minutes total.

Before dispatch, this active caller must supply the complete reviewer intake:

| Required input | Captured evidence |
|---|---|
| Repository and scope | Repository root, commit-review mode, included/excluded paths, and the assigned bounded reviewer scope. |
| Resolved identities | Base commit/empty-tree identity, resolved base tree `$baseSnapshot.Tree`, candidate tree `$candidate.Tree`, and the complete parent/ref approval tuple. Branch names alone are insufficient. |
| Complete diff and frozen context | `$candidate.DiffBytes`, including deletions, renames, binary/type changes; readable base/candidate paths and both path/mode/blob-ID manifests; immutable context for directly affected contracts. Supply manifests in the dispatch or an owned readable bundle. |
| Locked requirements | Applicable requirements, acceptance criteria, locked decisions, and explicitly unresolved questions, tied to the captured inputs. |
| Validation evidence | Exact validation commands, working directories, outcomes, coverage limits, and the covered candidate identity. Distinguish caller-executed checks from reviewer reading. |

Missing or unreadable required intake means **Incomplete - missing evidence**: name the missing inputs and bounded coverage, and stop dispatch or acceptance as a complete review.
Never substitute current files for missing immutable review evidence.
`code-reviewer` has `read` and `search` only; it returns bounded findings and evidence gaps to this active caller, without artifacts or workflow restart.

Each reviewer must:

- Return only concrete findings with file and line references plus a proposed correction.
- Focus on Critical and High severity concerns.
- Treat Medium and Low findings as non-blocking; record them only when they are concrete and valuable.
- Avoid style, formatting, and speculative concerns.

Required or user-requested review remains required for documentation. Assess
accuracy and meaningful contracts, not preferred phrasing; stylistic suggestions
must not become blockers or mandatory fix cycles.

Do not add replacement reviewers to extend the timebox.
If review coverage is incomplete when the timebox expires, report that limitation and let the user decide whether to continue this workflow. A requested `full-code-review` is a separate handoff only after this owning workflow has genuinely ended or been explicitly aborted; a blocked workflow is not complete.
Before accepting reviewer output, recheck both snapshots' integrity (base with `-Exact`) and the current candidate tuple; changed inputs require a newly identified intake.

Reviewers return findings only.
They must not create report files, directories, or other artifacts; this workflow owns consolidation and persistence.

## 6. Consolidate findings and decide

Deduplicate overlapping findings before presenting them.
For each finding, identify its status:

| Status | Meaning |
|---|---|
| **Commit blocker** | Unresolved Critical or High finding; cannot commit. |
| **Accepted risk** | User explicitly accepts a concrete Critical or High finding and directs the commit to continue where repository policy permits; this never waives required checks or delivery controls. |
| **Accepted exception** | User explicitly accepts a disclosed section 2.6 fidelity limitation and directs its bypass for the exact candidate; other gates remain required. |
| **Delayed follow-up** | Concrete Medium or Low finding recorded for later work. |
| **Explicitly dropped** | Concrete finding rejected with its rationale. |

Present blockers first, then accepted risks/exceptions, delayed follow-ups, and dropped findings. Never silently discard a finding or limitation. Offer eligible section 2.6 exceptions through `ask_user`; helper edits, generic commit requests, and silence are not acceptance. Record the full candidate tuple and approved bypass; refresh acceptance when either or the risks change. Include the exception in section 9's combined candidate/message approval, not instead of it.

## 7. Fix and scope re-review

Use existing scoped edit authorization for necessary fixes; a finding alone does
not expand it. For approval-controlled prose, present the exact proposed
replacement and obtain approval before applying or staging the wording change.
If the user declines, leave the text unchanged and disposition the finding:
optional polish may be dropped; a genuine blocker remains unless explicitly
accepted where policy permits. Commit approval is not advance wording approval.

After a fix, stage only the approved fix hunks and confirm the candidate still contains no unrelated changes.
Record the new tree ID through `New-GitReviewCandidate`, rematerialize the snapshot using section 2, and bind affected validation and re-review to that new candidate and its full base/parent/ref tuple.
Never validate an old snapshot after a fix or treat worktree-only results as evidence for the staged candidate.
Re-run direct validation for the changed files and affected targeted tests against the new snapshot.
Re-review only:

- Files modified by the fix.
- Previous finding locations.
- Directly affected contracts: public interfaces, abstract types, schemas, and public signatures the fix implements or depends on.

Do not rescan unchanged parts of the original diff.
Retain earlier findings for unchanged content, but refresh evidence for every affected contract.

The initial review is cycle one.
One targeted re-review is cycle two.
Before starting cycle three or any later cycle, use `ask_user` to obtain explicit approval for that individual additional cycle.
The cycle count never resets during a candidate's workflow.

## 8. Final validation gate

Once no unaccepted Critical or High finding remains, establish the checks
required for this commit boundary against the final staged snapshot.
Run a full suite only when repository policy requires it or affected behavior
warrants that scope. Otherwise use focused checks. Reuse still-valid evidence
under section 3 rather than repeating a suite merely because the phase changed.
Record the selected scope and coverage limits; do not run unrelated builds for
documentation or repeat full suites after every review or minor fix.

If no applicable suite exists, record **Not run - no applicable suite** and the coverage limitation, never a 0/0 pass.
Missing declared pre-commit checks remain blockers; this not-run case does not waive required validation.
Only the explicitly approved checkpoint exception permits post-commit/live
validation to remain pending; it is never a passing or inapplicable result.

Use `Invoke-GitSnapshotCheck` for each newly executed final-check command. After final validation and before final acceptance, require `Assert-GitSnapshotIntegrity -Snapshot $snapshot` and `Assert-GitCandidateCurrent -Candidate $candidate` to pass again. Ordinary untracked outputs may remain, but tracked paths/types/modes/bytes must still match the captured tree.
Also require `Assert-GitSnapshotIntegrity -Snapshot $baseSnapshot -Exact` so accepted review evidence still refers to the same immutable base context.
If a final check or an integrity gate fails, invalidate the affected evidence and return to the relevant fix and targeted re-review scope. Restoring inputs is not a substitute for rerunning checks.

## 9. Combined user verification and commit approval

Before committing:

1. Present the staged diff/summary and proposed message together with validation results (including reused and pending evidence), final blocker state, accepted risks and follow-ups, plus the exact approval tuple: repository/index source, base identity, ordered parent list, unborn/detached/symbolic ref state, destination ref, and candidate tree. For a checkpoint, identify its purpose and pending acceptance gates.
2. Use one confirmation for user verification and commit permission: use `ask_user` to obtain approval for the proposed conventional commit message **and that exact tuple**. Do not ask a separate preliminary verification question. Existing explicit approval of this presented candidate/message satisfies the gate; a generic earlier request to commit, silence or unavailable approval tooling does not. Evidence and approvals do not transfer to a different base, parent list, ref state, destination, or tree.
3. Immediately before committing, require `Assert-GitCandidateCurrent -Candidate $candidate` and `Assert-GitSnapshotIntegrity -Snapshot $snapshot` to pass. A same-tree HEAD advance, branch switch, unborn-to-born transition, detached/symbolic transition, or changed merge parent list invalidates approval. Stop and refresh the snapshot, affected checks, review, and approvals; tree equality alone is insufficient.
4. Create the commit only after approval, check its native exit status, and obtain its exact object ID with checked Git discovery. Verify the resulting commit tree, ordered parent list, destination ref, and ref state using `Assert-GitCandidateCommit -Candidate $candidate -CommitId <new-commit-id>`. An unborn candidate must produce a parentless commit at its approved branch; a detached candidate must remain detached. If a hook or concurrent operation changed the result, report the mismatch and stop delivery rather than claiming the commit was reviewed or amending it automatically. These pre/post gates detect mismatches, not an atomic lock against concurrent Git writers.

The commit message must use imperative mood, keep its subject to 72 characters or fewer, and include the required trailers:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
Copilot-Session: <current session ID>
```

Never amend a commit without explicit user approval.
Never commit secrets.

## 10. Record one compact outcome

This workflow owns consolidation and persistence, not the reviewers. Keep one
durable outcome record in the configured session provider or an existing
repository-required review record, not duplicate timelines. Routine clean
commits need a compact record, not a new planning document or detailed report.

Write a Markdown report only when requested, repository-required, or no durable
provider is available. Unless the repository specifies another location, use:

```text
.copilot/reports/reviews/{yyyy}/{MM}/commit-review-{dd}-{hhmmss}.md
```

Include:

- Candidate summary, complete approval tuple (including base, ordered parents, ref state, destination, and tree), resulting commit SHA or `ABORTED`/`PAUSED`, and normal/checkpoint purpose.
- Snapshot preflight, tracked-integrity gates, executed/reused final-check outcomes (including explicit not-run/coverage limitations), and post-commit tree/parent/ref verification.
- Intake identities and manifests, locked requirements, evidence references and missing-evidence limitations. Temporary snapshots are cleaned up; do not present their deleted paths as durable readable evidence.
- Reviewers used, selection rationale, and cycle count: exactly one core, zero or one ordinary relevant specialist, required signal-driven expertise, and a second specialist only for directly interacting distinct high-risk domains.
- Deduplicated findings grouped by the decision statuses.
- User approvals and the final outcome.
- Any timebox limitation.
- For checkpoints, accepted risks, blockers or unfinished handoffs: concrete
  pending checks, owner, trigger, acceptance gate and resume conditions.

Do not create a large intermediate report.
Update the same outcome when paused or handed off; append-only providers may
store a linked update rather than duplicating the timeline. A failed save must
be reported as unavailable persistence, not success or a reason to repeat a commit.
If using the fallback path and `/.copilot/` is not ignored, remind the user to add it to `.gitignore`.

## Related skills and agents

- After this owning workflow ends, use `full-code-review` only by separate explicit user invocation for release candidates, major architectural changes, security audits, schema redesigns, or exhaustive review requests.
- After this owning workflow ends, use `security-audit` only as a separate authorized workflow for a dedicated STRIDE and OWASP assessment.
- Use `code-reviewer` for an ad-hoc review that is not preparing a commit.
