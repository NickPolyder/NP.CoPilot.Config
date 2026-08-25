---
name: git-commit-review
description: >
  Lightweight pre-commit workflow that splits atomic candidates, validates an
  index-only snapshot, runs direct checks, and performs a targeted review before
  creating a safe, approved commit.
---

# Purpose

> **Intent (anchor):** Review one staged, logical diff quickly and create one safe, approved, atomic Git commit.
> **Always:** validate an index-only snapshot before reviewers; use direct validation before reviewer speculation; require manual user verification and an approved commit message; write one concise final report.
> **Never:** invoke `full-code-review` automatically; commit unresolved Critical or High findings; run more than two review cycles without explicit user approval.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs; `instructions/workflow.instructions.md` for proportional verification; and `instructions/git-conventions.instructions.md` for delivery and commit safety.

This is the default pre-commit workflow.
It is intentionally bounded to approximately ten minutes of reviewer time.

Use `full-code-review` only when the user explicitly requests exhaustive analysis.

## When to use this skill

Use this skill when a logical change is ready to commit.

Do not use it for:

- A user-requested full review, release candidate, major architectural change, security audit, or schema redesign; recommend `full-code-review`.
- A trivial change when the user explicitly chooses to skip review.
- An empty index.

## 1. Split atomic candidates and stage one

Inspect the worktree and divide it into logical, atomic commit candidates before adding reviewers.

- Keep one feature, fix, refactor, configuration change, or documentation concern in each candidate.
- Keep tests with the behavior they cover.
- Do not compensate for a large mixed diff by adding reviewers.
- Stage exactly one candidate with partial staging where necessary.
- Confirm the index contains no unrelated files or hunks.

If a candidate is not self-contained, split it before continuing.
Do not review unstaged changes or a mixture of candidates.

## 2. Materialize the clean index snapshot

Review the index, not the mutable worktree.

1. Require a non-empty `git diff --cached`.
2. Create a temporary directory outside the repository.
3. Materialize exactly the index tree into that directory, for example:

   ```powershell
   $tree = git write-tree
   git archive --format=tar $tree | tar -xf - -C $snapshotPath
   ```

   `git checkout-index --all --prefix="$snapshotPath\"` is an equivalent option.
4. Confirm the materialized file list matches `git diff --cached --name-only`, allowing only files intentionally excluded by Git attributes.
5. Keep the snapshot for validation and review, then remove it after the workflow.

Never substitute the working tree for this snapshot.
Unstaged changes must not affect validation or reviewer conclusions.

## 3. Direct validation preflight

Before dispatching a reviewer, run the repository's applicable import, restore, build, type-check, lint, and targeted-test commands against the index-only snapshot.

- Derive commands from repository documentation and manifests; do not invent a new toolchain.
- Prefer the narrowest checks that exercise the staged behavior.
- Run imports or compilation before tests so direct failures are surfaced first.
- Run the commands from the snapshot or point them at snapshot paths, never at the working tree.
- When the staged snapshot contains Copilot configuration files, run
  `pwsh -NoProfile -File .\scripts\Validate-Config.ps1 -RepositoryRoot $snapshotPath`
  before launching reviewers. Run its focused regression suite separately from
  the repository root when the staged changes affect the validator or its tests.

If the snapshot cannot be materialized, imports/build/type checks fail, or targeted tests fail, stop.
Report the concrete failure and fix it before launching any reviewer.
One proven clean-index failure is more valuable than speculative reviewer feedback.

## 4. Select reviewers and escalate risk

Start with exactly one core reviewer: `code-reviewer`.
Select at most one relevant specialist based on the staged snapshot.

| Staged-change signal | Specialist |
|---|---|
| Authentication, authorization, cryptography, secrets | `security-engineer` |
| Destructive or irreversible database migration; safety-critical data integrity | `database-engineer` |
| External production writes; integration-side data integrity | `systems-engineer` |
| Deployment or infrastructure change with broad blast radius | `devops-engineer` |
| Safety-critical concurrency | `systems-engineer` or the primary affected domain specialist |

These signals automatically add the appropriate specialist; they never invoke `full-code-review`.

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

Each reviewer must:

- Return only concrete findings with file and line references plus a proposed correction.
- Focus on Critical and High severity concerns.
- Treat Medium and Low findings as non-blocking; record them only when they are concrete and valuable.
- Avoid style, formatting, and speculative concerns.

Do not add replacement reviewers to extend the timebox.
If review coverage is incomplete when the timebox expires, say so in the final report and let the user decide whether to continue or invoke `full-code-review`.

Reviewers return findings only.
They must not create report files, directories, or other artifacts; this workflow owns consolidation and persistence.

## 6. Consolidate findings and decide

Deduplicate overlapping findings before presenting them.
For each finding, identify its status:

| Status | Meaning |
|---|---|
| **Commit blocker** | Unresolved Critical or High finding; cannot commit. |
| **Accepted risk** | User explicitly accepts a concrete Critical or High finding and directs the commit to continue. |
| **Delayed follow-up** | Concrete Medium or Low finding recorded for later work. |
| **Explicitly dropped** | Concrete finding rejected with its rationale. |

Present blockers first, then accepted risks, delayed follow-ups, and dropped findings.
Never silently discard a concrete finding.

## 7. Fix and scope re-review

After a fix, re-run direct validation for the changed files and affected targeted tests.
Re-review only:

- Files modified by the fix.
- Previous finding locations.
- Directly affected contracts: public interfaces, abstract types, schemas, and public signatures the fix implements or depends on.

Do not rescan the original diff.

The initial review is cycle one.
One targeted re-review is cycle two.
Before starting cycle three or any later cycle, use `ask_user` to obtain explicit approval for that individual additional cycle.
The cycle count never resets during a candidate's workflow.

## 8. Final validation gate

Once no unaccepted Critical or High finding remains, run the repository's full existing test suite once against the final staged snapshot.
Do not run the full suite after every review or minor fix.

If the full suite fails, return to the relevant fix and targeted re-review scope.

## 9. User verification and commit

Before committing:

1. Present the staged candidate summary, validation results, final blocker state, accepted risks, and delayed follow-ups.
2. Require the user to manually verify the changes.
3. After confirmation, use `ask_user` to obtain approval for the proposed conventional commit message.
4. Create the commit only after approval.

The commit message must use imperative mood, keep its subject to 72 characters or fewer, and include the required trailers:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
Copilot-Session: <current session ID>
```

Never amend a commit without explicit user approval.
Never commit secrets.

## 10. Persist one final report

After consolidating reviewer findings and recording their dispositions, write one concise final report for the candidate at:

```text
.copilot/reports/reviews/{yyyy}/{MM}/commit-review-{dd}-{hhmmss}.md
```

Include:

- Candidate summary and resulting commit SHA, or `ABORTED`.
- Snapshot preflight and final-suite outcomes.
- Reviewers used, selection rationale, and cycle count.
- Deduplicated findings grouped by the four decision statuses.
- User approvals and the final outcome.
- Any timebox limitation.

Do not create a large intermediate report.
Persist an intermediate blocker record only when a Critical or High finding exists and the workflow is paused or handed off.
If `/.copilot/` is not ignored, remind the user to add it to `.gitignore`.

## Related skills and agents

- Use `full-code-review` only by explicit user invocation for release candidates, major architectural changes, security audits, schema redesigns, or exhaustive review requests.
- Use `security-audit` for a dedicated STRIDE and OWASP assessment.
- Use `code-reviewer` for an ad-hoc review that is not preparing a commit.

## Final Rules (Anchor)

1. Materialize and validate an index-only snapshot before launching reviewers.
2. Use one `code-reviewer`, at most one ordinary specialist, and a second specialist only for high-risk cross-domain changes.
3. Never commit unresolved Critical or High findings unless the user explicitly accepts the risk and directs the commit.
4. Never auto-invoke `full-code-review`.
5. Never exceed two review cycles without explicit user approval for each additional cycle.
6. Never amend a previous commit unless the user explicitly asks.
