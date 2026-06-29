---
name: test-gap-analysis
description: >
  Retroactively audits existing code for untested paths, weak assertions,
  and missing edge case coverage. Identifies what should have been caught
  and generates concrete test cases to fill the gaps.
tags:
  - testing
  - coverage
  - quality
  - gaps
  - retroactive
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles]
---

# Purpose

> **Intent (anchor):** Coordinate a two-phase test-gap workflow — audit first, then optionally fill — by sequencing the atomic `test-gap-audit` and `test-gap-fill` skills behind an approval gate.
> **Always:** run the read-only audit before generating anything; require explicit approval of which gaps to fill; keep audit and fill as separate atomic steps.
> **Never:** generate tests before the gap report is approved, or modify production code without asking.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

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
real bugs the new tests expose. It does not modify production code without asking.

---

# Coordination

- **`test-gap-audit`** — the read-only gap report (Step 1).
- **`test-gap-fill`** — the approved test generation (Step 2).
- **Consult `qa-engineer`** — for test strategy questions, fixture design, and coverage philosophy.
- **Consult `backend-developer`** — for understanding domain logic intent when generating tests.
- **Consult `security-engineer`** — when gaps are found in security-sensitive code paths.
- **Recommend `refactor`** — if existing tests need structural cleanup before new tests fit cleanly; do not invoke it from this skill.

---

# Constraints

- **Audit before fill** — always run `test-gap-audit` (read-only) before generating tests.
- **Approval gate is mandatory** — never start test generation without explicit user approval.
- **Keep the steps atomic** — do not blend audit and generation logic here; delegate to the two skills.
- **Don't modify production code** — this flow adds/improves tests; if a bug is found, report it and ask before fixing.
- **This skill is not an orchestrator** — it does not invoke other orchestrator skills.

---

## Final Rules (Anchor)

1. Always audit (read-only) before filling — never skip the `test-gap-audit` step.
2. The approval gate between audit and fill is mandatory — never generate tests without explicit approval.
3. Don't modify production code; delegate the detailed work to the two atomic skills and keep this coordinator thin.
> If anything above conflicts with these, **these win**.
