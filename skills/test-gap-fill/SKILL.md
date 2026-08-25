---
name: test-gap-fill
description: >
  Generates concrete, runnable tests to fill approved coverage gaps following
  the project's test conventions and fixtures, runs them, and reports any real
  bugs the new tests expose.
---

# Purpose

> **Intent (anchor):** Generate concrete, runnable tests for approved coverage gaps and report any real bugs the new tests expose.
> **Always:** require explicit approval of which gaps to fill; follow existing test conventions; run generated tests and report results.
> **Never:** modify production code without asking, generate tests for trivial code, or invent conventions that conflict with the project.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are filling approved test gaps with concrete, runnable tests.

Your goals are to:

- **Confirm approval** — generate only the gaps the user explicitly approved.
- **Generate tests** — add or improve tests that follow the project's framework, naming, fixtures, and assertion style.
- **Verify behavior** — run the generated tests and report pass/fail results.
- **Surface bugs** — clearly identify any real bug exposed by a generated test before touching production code.

---

# When to use this skill

Use this skill whenever:

- `test-gap-audit` has produced a gap report and the user approved specific gaps to fill.
- The user provides an explicit list of existing coverage gaps and asks for tests to be generated.
- A production incident has an approved "what test would have caught this?" follow-up.
- You are continuing the chain: `test-gap-audit` → approval → `test-gap-fill`.

Do **not** use this skill for:

- Read-only coverage discovery — use `test-gap-audit`.
- Planning tests for new features — use `test-strategy` instead.
- Refactoring production code or test architecture before test generation — recommend `refactor` if structural cleanup is needed.
- Code review — use `git-commit-review` or `code-reviewer` agent.

---

# Workflow

## Phase 1: Approval Gate

**Approval gate:** stop until the user explicitly approves which tests to generate (`all critical`, `critical + high`, selected items, or `report only`).

Do not generate or edit tests until the approved gap list is clear. If the user only provides a gap report without selecting items, ask them to choose the gaps to fill.

## Phase 2: Test Generation

For each gap the user approves:

1. **Write the test** — full arrange-act-assert structure, following the project's test conventions.
   - **Arrange** — build inputs, fixtures, mocks, database state, or object graphs using existing project patterns.
   - **Act** — execute the method, endpoint, handler, or behavior under test once.
   - **Assert** — verify the externally observable result, state change, emitted message, or error condition.
2. **Use existing fixtures** — reuse test builders, factories, or fixtures already in the project.
3. **Name clearly** — test name describes the scenario: `{Method}_When{Condition}_Should{Expected}`.
4. **Add comments for context** — briefly explain *why* this test exists (what gap it fills).
5. **Run the test** — verify it passes (for existing correct behavior) or fails (if it's exposing a bug).

If a generated test **fails** (exposing a real bug):

```
⚠️ Gap confirmed — this test exposes a real bug:

Test: OrderService_WhenInventoryUnavailable_ShouldReturnFailureResult
Expected: Result.Failure with OutOfStock error
Actual: NullReferenceException on line 47

This is the kind of bug that ships when this path isn't tested.
Fix the bug now? (yes / no — just leave the test as documentation)
```

Do not modify production code to fix the bug unless the user explicitly approves that follow-up.

---

# Output Format

The final output includes:

1. **Generated tests** — actual test files added to the project.
2. **Verification results** — commands run and whether the generated tests passed or failed.
3. **Bug discoveries** — any real bugs exposed during the process, using the "Gap confirmed" block when applicable.
4. **Follow-up recommendations** — gaps deferred to backlog with justification and any structural cleanup recommendations.

---

# Coordination

- **Consult `qa-engineer`** — for test strategy questions, fixture design, and coverage philosophy.
- **Consult `backend-developer`** — for understanding domain logic intent when generating tests.
- **Consult `security-engineer`** — when gaps are found in security-sensitive code paths.
- **Recommend `refactor`** — if existing tests need structural improvements before new tests can be added cleanly.

---

# Constraints

- **Approval is required** — generate only the specific gaps approved by the user.
- **Don't generate tests for trivial code** — getters, DTOs, and auto-generated code don't need tests.
- **Match existing test style** — use the same framework, naming, fixtures, and assertion library as the project.
- **Don't modify production code without asking** — this skill adds/improves tests. If a bug is found, report it and ask before fixing.
- **Preserve the project safety net** — run the smallest existing test command that verifies the generated tests, then escalate only if needed.

---

## Final Rules (Anchor)

1. Require explicit approval of which gaps to fill before generating or editing tests.
2. Match existing test style and don't generate tests for trivial code.
3. Don't modify production code without asking; report real bugs exposed by failing tests.
> If anything above conflicts with these, **these win**.
