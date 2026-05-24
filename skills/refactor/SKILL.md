---
name: refactor
description: >
  Structured refactoring with safety nets. Establishes baseline (tests pass),
  makes incremental changes, verifies after each step, and produces clean
  atomic commits. Prevents regressions through disciplined verify-after-change.
tags:
  - refactoring
  - code-quality
  - safety
  - incremental
visibility: user
tools:
  [agent, edit/editFiles, todo]
---

# Purpose

You are executing a disciplined refactoring process with safety guarantees.

Your goals are to:

- **Preserve behavior** — refactoring changes structure, not behavior.
- **Verify continuously** — tests must pass after every atomic step.
- **Work incrementally** — small, reversible changes, not big-bang rewrites.
- **Produce clean commits** — each commit is a single refactoring step that compiles and passes tests.

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
- Trivial renames with no structural impact — just do them (Trivial tier).

---

# Workflow

## Phase 1: Establish Baseline

Before touching anything:

1. **Run the full test suite** — record pass/fail counts. This is your safety net.
2. **If tests are failing** — STOP. Do not refactor against a broken baseline. Report the failures and ask the user how to proceed.
3. **Identify the refactoring scope** — which files, classes, or modules are affected?
4. **Check for coverage** — are the areas you're refactoring covered by tests? If not, flag this as a risk.

Present:

```
### Refactoring Baseline

**Test suite:** {passed}/{total} passing, {skipped} skipped
**Scope:** {files/classes to be changed}
**Coverage risk:** {High — untested code | Low — well-covered}

Proceed with refactoring? (yes / no / write tests first)
```

If coverage is low, recommend writing characterization tests first (tests that capture current behavior, even if it's not ideal).

## Phase 2: Plan Steps

Break the refactoring into **atomic, independently verifiable steps**:

1. Each step should be one refactoring operation (extract method, rename class, move file, etc.).
2. Each step must leave the code in a compilable, test-passing state.
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
2. **Build** — verify compilation (`dotnet build` or equivalent).
3. **Test** — run the test suite. All previously-passing tests must still pass.
4. **If tests fail** — revert the step and reassess. Either the refactoring changed behavior (bug in the refactoring) or the tests were brittle (worth fixing separately).

After all steps complete:

```
### Refactoring Complete

**Steps executed:** {N}/{N}
**Final test suite:** {passed}/{total} passing
**Behavior changes:** None (verified by tests)
**Files modified:** {list}

Ready to commit? (yes / review changes first)
```

## Phase 4: Commit

Commit strategy depends on the refactoring size:

- **Small refactoring (1–3 steps):** One commit with a clear message.
- **Large refactoring (4+ steps):** Consider multiple commits, one per logical group of steps. Each commit must independently compile and pass tests.

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

- **Consult `architect`** — when the refactoring changes architectural boundaries or layer responsibilities.
- **Consult `backend-developer`** — for .NET-specific refactoring patterns and EF Core implications.
- **Consult `qa-engineer`** — when existing test coverage is insufficient and characterization tests are needed.

---

# Constraints

- **Tests must pass after every step.** No exceptions. A failing intermediate state means the step was wrong.
- **Never combine refactoring with behavior changes** in the same commit. If you discover a bug during refactoring, commit the refactoring first, then fix the bug in a separate commit.
- **Don't refactor code you don't understand** — read it first, understand the intent, then restructure.
- **This skill is not an orchestrator** — it doesn't invoke `git-commit-review` or other orchestrator skills. It follows the Standard tier workflow for commits.
- **Respect the scope** — don't expand the refactoring beyond what was agreed. If you see adjacent code that needs work, note it as a follow-up.
