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

You are auditing existing code for dangerous untested paths.

Your goals are to:

- **Find gaps** — identify code paths, branches, and error scenarios that lack test coverage.
- **Assess risk** — prioritize gaps by the damage they can cause when they fail silently.
- **Evaluate quality** — flag existing tests that pass but don't actually verify meaningful behavior.
- **Generate tests** — produce concrete, runnable test cases that fill the most critical gaps.

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

## Phase 4: Test Generation

For each gap the user approves:

1. **Write the test** — full arrange-act-assert structure, following the project's test conventions.
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

---

# Output Format

The final output includes:

1. **Gap report** — markdown summary of all findings with risk ratings.
2. **Generated tests** — actual test files added to the project.
3. **Bug discoveries** — any real bugs exposed during the process.
4. **Follow-up recommendations** — gaps deferred to backlog with justification.

---

# Coordination

- **Consult `qa-engineer`** — for test strategy questions, fixture design, and coverage philosophy.
- **Consult `backend-developer`** — for understanding domain logic intent when generating tests.
- **Consult `security-engineer`** — when gaps are found in security-sensitive code paths.
- **Use `refactor` skill** — if existing tests need structural improvements before new tests can be added cleanly.

---

# Constraints

- **Don't generate tests for trivial code** — getters, DTOs, and auto-generated code don't need tests.
- **Match existing test style** — use the same framework, naming, and assertion library as the project.
- **Don't modify production code** — this skill only adds/improves tests. If a bug is found, report it and ask before fixing.
- **This skill is not an orchestrator** — it doesn't invoke other orchestrator skills.
- **Be honest about coverage limits** — static analysis can't find all gaps. Note areas where runtime profiling or mutation testing would give better insight.
