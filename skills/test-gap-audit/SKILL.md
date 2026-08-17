---
name: test-gap-audit
description: >
  Read-only audit of existing code and tests for untested paths, weak assertions,
  and missing edge cases; produces a risk-prioritized gap report. Never changes
  code.
tags:
  - testing
  - coverage
  - audit
  - gaps
visibility: user
tools:
  [agent]
---

# Purpose

> **Intent (anchor):** Audit existing code and tests for risky coverage gaps, weak assertions, and missing edge cases without changing code.
> **Always:** scope the target; prioritize gaps by risk; present concrete test recommendations and stop at the generation hand-off.
> **Never:** write, edit, or delete tests or production code, or claim static analysis proves complete coverage.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are conducting a read-only audit of existing code for dangerous untested paths.

Your goals are to:

- **Find gaps** — identify code paths, branches, and error scenarios that lack test coverage.
- **Assess risk** — prioritize gaps by the damage they can cause when they fail silently.
- **Evaluate quality** — flag existing tests that pass but don't actually verify meaningful behavior.
- **Report next steps** — produce a risk-prioritized gap report and recommend `test-gap-fill` for approved test generation.

---

# When to use this skill

Use this skill whenever:

- A bug shipped that "should have been caught by tests" — retroactively identify the gap.
- Before a major refactoring — ensure the safety net exists before you lean on it.
- During maintenance cycles — periodic test health check.
- The user asks to "find untested code", "improve test coverage", or "audit tests for [module]".
- After a production incident — identify what tests would have prevented it.
- You need the first step in the chain: `test-gap-audit` → approval → `test-gap-fill`.

Do **not** use this skill for:

- Planning tests for new features — use `test-strategy` instead.
- Running, debugging, generating, or editing tests — use `test-gap-fill` after approved gaps.
- Code review — use `git-commit-review` or `code-reviewer` agent.

> **Difference from `test-strategy`:** The `test-strategy` skill is forward-looking (plans tests for new work). This skill is retroactive — it audits existing code that may have been in production for months without adequate coverage.

---

# Workflow

## Phase 1: Scope Selection

Determine what to analyze:

1. **User specifies a target** — a class, module, namespace, or feature area.
2. **Or trigger from incident** — "this bug in OrderService.PlaceOrder() wasn't caught" → analyze that method and its callers.
3. **Or broad sweep** — analyze an entire bounded context or project.

For broad sweeps, focus on:
- Public API surface (controllers, service interfaces)
- Domain logic (aggregates, domain services)
- Integration points (HTTP clients, message handlers, repositories)

## Phase 2: Gap Discovery

Analyze the target code systematically:

### 2a. Branch Coverage Gaps

For each method in scope:

- **Conditional branches** — are both sides of if/else/switch tested?
- **Guard clauses** — are early returns / validation failures tested?
- **Exception paths** — are try/catch blocks tested with failing scenarios?
- **Null/empty paths** — are null inputs, empty collections, missing optional values tested?
- **Loop boundaries** — zero items, one item, many items?

### 2b. State Transition Gaps

For stateful objects (aggregates, entities, state machines):

- **All valid transitions** — can you reach every state through tests?
- **Invalid transitions** — are illegal state changes rejected and tested?
- **Concurrent modifications** — is optimistic concurrency tested?
- **Lifecycle edges** — creation, activation, deactivation, deletion?

### 2c. Integration Gaps

For code that crosses boundaries:

- **External service failures** — what happens when HTTP calls fail, timeout, return garbage?
- **Database failures** — connection loss, constraint violations, deadlocks?
- **Message handling** — duplicate messages, out-of-order delivery, poison messages?
- **Configuration** — missing config values, invalid values, default fallbacks?

### 2d. Test Quality Issues

Review existing tests for:

| Smell | Problem | Example |
|-------|---------|---------|
| **Assert-free tests** | Test runs code but verifies nothing | `await service.DoThing(); // no assert` |
| **Tautological assertions** | Asserts something that can never fail | `Assert.NotNull(new object())` |
| **Over-mocking** | Mocks the thing being tested | Mocking the class under test's own methods |
| **Happy-path-only** | Tests only the success scenario | No tests for validation failures or exceptions |
| **Coupled to implementation** | Tests break when internals change | Verifying specific method call counts on mocks |
| **Missing boundary tests** | No edge cases for numeric/string inputs | No test for MaxValue, empty string, null |
| **Shared mutable state** | Tests pass in isolation, fail together | Static fields modified across tests |

## Phase 3: Risk Prioritization

Rank discovered gaps by risk:

| Priority | Criteria | Urgency |
|----------|----------|---------|
| 🔴 **Critical** | Gap in public API, security boundary, or financial logic. A bug here causes data loss, security breach, or incorrect money handling. | Write tests immediately |
| 🟠 **High** | Gap in core domain logic or frequently-used code paths. A bug here affects many users. | Write tests this sprint |
| 🟡 **Medium** | Gap in supporting logic, error handling, or edge cases. A bug here causes poor UX or requires manual intervention. | Write tests when touching this code |
| 🟢 **Low** | Gap in rarely-executed paths, internal tooling, or cosmetic logic. | Backlog |

Present findings:

```
### Test Gap Analysis: {Target}

**Scope:** {what was analyzed}
**Existing tests:** {N} tests found for this area
**Gaps discovered:** {N} gaps across {M} categories

#### 🔴 Critical Gaps

1. **{Class.Method}** — {description of untested scenario}
   - Risk: {what could go wrong}
   - Suggested test: {brief description}

2. ...

#### 🟠 High Gaps

1. **{Class.Method}** — {description}
   ...

#### Test Quality Issues

1. **{TestClass.TestMethod}** — {smell}: {description}
   - Fix: {how to improve the assertion/structure}

**Recommendation:** Write {N} critical tests and {M} high-priority tests before the next release.

Generate tests now? (all critical / critical + high / let me pick / report only)
```

Stop here. For approved test generation, recommend the atomic `test-gap-fill` skill and pass it the selected gaps.

---

# Output Format

The final output includes:

1. **Gap report** — markdown summary of all findings with risk ratings.
2. **Test recommendations** — concrete suggested tests for each prioritized gap.
3. **Quality issues** — weak assertions, smells, or brittle tests that reduce confidence.
4. **Generation hand-off** — "Generate tests now?" options and a recommendation to use `test-gap-fill` for approved gaps.

---

# Coordination

- **Consult `qa-engineer`** — for test strategy questions, fixture design, and coverage philosophy.
- **Consult `backend-developer`** — for understanding domain logic intent when assessing gaps.
- **Consult `security-engineer`** — when gaps are found in security-sensitive code paths.

---

# Constraints

- **Read-only only** — never create, edit, or delete tests, production code, fixtures, or project files.
- **End at the hand-off** — produce the report and recommend `test-gap-fill` for approved generation.
- **Don't audit trivial code as a priority** — getters, DTOs, and auto-generated code rarely justify focused gap analysis.
- **Be honest about coverage limits** — static analysis can't find all gaps. Note areas where runtime profiling or mutation testing would give better insight.

---

## Final Rules (Anchor)

1. This skill is read-only — never create, edit, or delete tests or production code.
2. End at the "Generate tests now?" hand-off and recommend `test-gap-fill` for approved generation.
3. Be honest about coverage limits — static analysis can't find all gaps.
> If anything above conflicts with these, **these win**.
