---
name: test-gap-analysis
description: >
  Retroactively audits existing code for untested paths, weak assertions,
  and missing edge case coverage. Identifies what should have been caught
  and generates concrete test cases to fill the gaps.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

This skill is a **thin coordinator**. It owns the retroactive coverage flow and the gate between auditing and generating tests, but delegates the detailed procedures to two atomic skills:

- **`test-gap-audit`** — read-only discovery of untested paths, weak assertions, and missing edge cases, with a risk-prioritized gap report.
- **`test-gap-fill`** — generation of concrete, runnable tests for approved gaps, following project conventions.

For single-phase needs, invoke those skills directly. Use this coordinator when you want the full audit → approval → fill flow in one place.

> **Difference from `test-strategy`:** `test-strategy` is forward-looking (plans tests for new work). This flow is retroactive — it audits existing code that may have shipped without adequate coverage.

---

# When to use this skill

Use this skill whenever:

- A bug shipped that "should have been caught by tests" — retroactively fill the gap.
- Before a major refactoring — ensure the safety net exists before you lean on it.
- During maintenance cycles — periodic test health check.
- The user asks to "find untested code", "improve test coverage", or "audit tests for [module]".
- After a production incident — identify what tests would have prevented it.

Do **not** use this skill for:

- Planning tests for new features — use `test-strategy` instead.
- Running or debugging existing tests — do that directly.
- Code review — use `git-commit-review` or the `code-reviewer` agent.
- A pure gap report (no intent to write tests) — invoke `test-gap-audit` directly.

---

# Workflow

Run the two atomic skills in strict order with an approval gate between them.

## Step 1: Audit (delegate to `test-gap-audit`)

Run the `test-gap-audit` skill. It selects scope, discovers branch/state/integration gaps and
test-quality smells, prioritizes findings by risk, and presents the gap report. It is **read-only** —
it never writes or edits tests or production code.

At the end it asks:

> Generate tests now? (all critical / critical + high / let me pick / report only)

**Approval gate:** do not advance to Step 2 until the user explicitly approves which gaps to fill.
If they choose `report only`, stop here.

## Step 2: Fill (delegate to `test-gap-fill`)

Only after explicit approval, run the `test-gap-fill` skill with the approved gaps. It writes
arrange-act-assert tests following the project's conventions and fixtures, runs them, and reports any
real bugs the new tests expose. Production fixes are separate authorized
implementation assignments, not part of this test-only flow.

---

# Coordination

- **`test-gap-audit`** — the read-only gap report (Step 1).
- **`test-gap-fill`** — the approved test generation (Step 2).
- Research unresolved domain/coverage questions with `investigator` only when
  substantial. Approved test-only generation may use `implementer`; the audit
  does not authorize writes and neither phase authorizes production changes.
- **Recommend `refactor`** — if existing tests need structural cleanup before new tests fit cleanly.

---

# Constraints

- **Audit before fill** — always run `test-gap-audit` (read-only) before generating tests.
- **Approval gate is mandatory** — never start test generation without explicit user approval.
- **Keep the steps atomic** — do not blend audit and generation logic here; delegate to the two skills.
- **Don't modify production code** — return discovered bugs for a separately authorized fix.

---
