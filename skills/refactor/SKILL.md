---
name: refactor
description: >
  Structured refactoring with safety nets. Establishes baseline (tests pass),
  makes incremental changes, verifies after each step, and prepares an atomic
  commit-review handoff. Reports coverage limits and residual regression risk.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are executing a disciplined refactoring process with evidence-based safety checks.

Your goals are to:

- **Preserve behavior** — refactoring changes structure, not behavior.
- **Verify continuously** — all required tests and agreed verification checks
  must pass after every atomic step; missing coverage remains explicit.
- **Work incrementally** — small, reversible changes, not big-bang rewrites.
- **Prepare clean commit-review handoff** — when refactoring is verified, recommend `git-commit-review` rather than owning commit strategy.

---

# When to use this skill

Use this skill whenever:

- Restructuring code without changing its behavior (rename, extract, move, inline, etc.).
- The user asks to "refactor", "clean up", "reorganize", or "restructure" code.
- Preparatory refactoring before a feature (making the codebase ready for a change).
- Reducing technical debt in a specific area.

Do **not** use this skill for:

- Adding new features or behavior — that's implementation, not refactoring.
- Bug fixes that change behavior — fix the bug directly.
- Simple renames with no structural impact — do them directly.

---

# Workflow

## Phase 1: Establish Baseline

Before touching anything:

1. **Run the existing test baseline** — use the repository-required scope and
   record pass/fail counts and unavailable checks. This is your safety net.
2. **If tests are failing** — HARD STOP. Do not refactor against a broken baseline. Report the failures and do not proceed until the baseline is fixed outside this refactoring.
3. **Identify the refactoring scope** — which files, classes, or modules are affected?
4. **Check for coverage** — map executed tests to the changed behaviors and
   record measured coverage, untested paths, and missing measurements. Passing
   tests or a coverage percentage do not establish that all behavior is covered.
5. **Bind the evidence** — record baseline revision, command, working directory,
   scope, result, and skips. If no applicable runner exists, report that fact,
   not a passing `0/0` suite; do not proceed without a policy-permitted, explicitly
   agreed verification alternative and its limitations.

Present:

```
### Refactoring Baseline

**Test suite:** {actual pass/fail/skip counts, or not run with reason}
**Evidence:** {revision; commands + working directories; unavailable checks}
**Scope:** {files/classes to be changed}
**Coverage:** {measured coverage and source, or not measured; changed paths not exercised}
**Residual risk:** {what the available checks cannot establish}

Proceed with refactoring? (yes / no / write tests first)
```

If coverage is low or unmeasured, recommend characterization tests first (tests
that capture current behavior, even if it is not ideal). If the user accepts
proceeding with limited coverage and project policy permits it, record the exact
gap and acceptance and carry them into the final outcome. This is not acceptance
of failing required checks. A failing baseline is a hard stop: do not refactor
until required tests/build are green or the user changes scope to a separate fix.

## Phase 2: Plan Steps

Break the refactoring into **atomic, independently verifiable steps**:

1. Each step should be one refactoring operation (extract method, rename class, move file, etc.).
2. Each step must pass applicable build/tests and any explicitly agreed
   verification alternative; no failing required check may be waived silently.
3. Order steps to minimize risk — prefer steps that reduce scope (extract → move → delete) over steps that expand scope.

Present the plan:

```
### Refactoring Plan

1. {Step 1 — description} (affects: {files})
2. {Step 2 — description} (affects: {files})
3. {Step 3 — description} (affects: {files})

Estimated steps: {N}
Approve plan? (yes / no / adjust)
```

## Phase 3: Execute

For each step:

1. **Make the change** — one refactoring operation.
2. **Build** — run the target's applicable compilation/type checks from its
   declared cwd; do not invent a build for a target without one.
3. **Test** — run the required suite or the explicitly agreed no-runner
   verification alternative. All previously-passing required checks must still pass.
4. **If tests fail** — stop and reassess; undo only this step's owned changes if
   safe, preserving unrelated user/concurrent edits. Either behavior changed or
   tests were brittle; do not weaken tests or conceal the failure to continue.

After all steps complete:

```
### Refactoring Outcome

**Status:** {completed steps | partial | blocked}
**Steps executed:** {executed}/{planned}
**Final evidence:** {revision; commands/cwds; passed/failed/skipped or not-run results}
**Behavior intent:** No intentional behavior change
**Observed result:** {regressions observed, or none observed in the checks actually executed}
**Coverage limits:** {untested changed paths; unmeasured coverage; unavailable checks}
**Accepted residual risk:** {specific gap and approval, or none}
**Files modified:** {list}

Ready for a separate commit review? (yes / review changes first)
```

## Phase 4: Commit Review Recommendation

When this refactoring workflow has completed its state, recommend a separate
`git-commit-review` workflow. Provide executed steps, modified files, revision-bound
verification, coverage limits, accepted residual risks, and follow-ups. Do not
equate passing a weak suite with proof of unchanged behavior or embed commit
creation/approval inside this skill.

---

# Refactoring Catalog

Common refactoring operations and their safety considerations:

| Refactoring | Risk | Verification |
|-------------|------|--------------|
| Rename (class, method, property) | Low — IDE can catch most references | Build + test |
| Extract method/class | Low — preserves behavior by construction | Build + test |
| Move to another file/namespace | Medium — can break using statements, DI registrations | Build + test + verify DI |
| Inline (method, variable) | Low — simplification | Build + test |
| Change method signature | Medium — affects all callers | Build + test |
| Replace inheritance with composition | High — behavioral difference possible | Build + test + manual review |
| Split class into multiple | Medium — DI and coupling changes | Build + test + verify DI |
| Introduce interface/abstraction | Low — additive change | Build + test |
| Remove dead code | Low — if truly dead | Build + test + grep for references |

---

# Coordination

- Use `investigator` for substantial unresolved boundary, framework or
  characterization-strategy questions. Approved refactoring or test work may go
  to `implementer` with the exact scope and verification contract; small steps
  stay inline. A test-only assignment does not acquire production ownership.

---

# Constraints

- **Required checks must pass after every step.** A failing intermediate state
  blocks continuation; an agreed no-runner alternative never hides missing coverage.
- **Never combine refactoring with behavior changes** in the same candidate.
  Return discovered bugs as separate follow-ups or blockers; this skill does not
  create a commit to bypass their disposition.
- **Don't refactor code you don't understand** — read it first, understand the intent, then restructure.
- **Commit review is a handoff** — recommend `git-commit-review` for commits; this workflow does not define commit strategy.
- **Respect the scope** — don't expand the refactoring beyond what was agreed. If you see adjacent code that needs work, note it as a follow-up.

---
