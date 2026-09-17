---
name: test-strategy
description: >
  Analyzes code changes or a feature area and generates a comprehensive test
  strategy with coverage plan, edge case discovery, test data approach, and
  prioritized test cases. Coordinates with developer agents for implementation.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are creating a forward-looking test strategy for a feature or code change.

Your goals are to:

- **Analyze the feature/code** to understand what needs testing.
- **Design a test pyramid** — allocate unit, integration, and E2E tests appropriately.
- **Discover edge cases** systematically using structured techniques.
- **Define test data strategy** — how test data is created, managed, and cleaned up.
- **Produce prioritized test cases** that developers can implement later.
- **Identify coverage risks** and existing test signals that should shape the plan.

---

# When to use this skill

Use this skill whenever:

- A new feature needs a test plan before or during implementation.
- The user asks for a test strategy, test plan, or coverage analysis.
- Existing tests need context for planning upcoming work, without retroactive gap filling.
- A critical upcoming module needs comprehensive test coverage.

Do **not** use this skill for:

- Writing individual test implementations (developers do that; this skill plans the strategy).
- Pre-commit reviews (use the `git-commit-review` skill).
- General code reviews (use the `code-reviewer` agent).
- Retroactively auditing existing code/tests or filling discovered gaps — use
  `test-gap-analysis`.

---

# Strategy process

## Step 1: Analyze the target

Understand what you're creating a test strategy for:

1. **Read the code** — understand the components, services, and data flow.
2. **Identify the domain** — what business logic is involved?
3. **Map the dependencies** — what does this code depend on? What depends on it?
4. **Check existing tests** — what's already tested? What's missing?
5. **Identify risk areas** — where would bugs cause the most damage?

## Step 2: Risk-based prioritization

Categorize areas by risk level:

| Risk Level | Criteria | Test Depth |
|---|---|---|
| 🔴 **Critical** | Data integrity, security, financial, core business flow | Unit + Integration + E2E |
| 🟠 **High** | Core user workflows, data mutations, complex logic | Unit + Integration |
| 🟡 **Medium** | Standard CRUD, UI components, straightforward logic | Unit + selective Integration |
| 🟢 **Low** | Display-only, static content, simple getters | Unit or manual verification |

## Step 3: Design the test pyramid

Allocate tests across levels:

```
         ╱  E2E Tests  ╲          ~5-10% of tests
        ╱   (Playwright) ╲        Critical user journeys ONLY
       ╱──────────────────╲
      ╱ Integration Tests   ╲     ~20-30% of tests
     ╱  (WebAppFactory,      ╲    API, database, services
    ╱   TestContainers)       ╲
   ╱──────────────────────────╲
  ╱      Unit Tests            ╲  ~60-70% of tests
 ╱  (xUnit, Jest, bUnit)       ╲  Business logic, components
╱──────────────────────────────╲
```

For each level, define:

### Unit Tests

What to unit test:
- Domain entities and value objects (business rules, invariants)
- Application services and handlers (orchestration logic)
- Validators (input validation rules)
- Utility/helper methods (calculations, transformations)
- Angular/Blazor components (rendering, interactions)
- Pipes, directives, services (frontend logic)

What NOT to unit test:
- Framework code (EF Core, ASP.NET Core pipeline)
- Trivial getters/setters
- Third-party library wrappers (test at integration level)
- Configuration classes

### Integration Tests

What to integration test:
- API endpoints (request → response cycle)
- Database operations (repository → actual database)
- Message consumers (message → handler → effect)
- External service calls (with test doubles or stubs)
- Authentication/authorization pipeline
- Middleware behavior

### E2E Tests

What to E2E test:
- Critical user journeys (login, core workflow, checkout)
- Cross-cutting flows (error recovery, session handling)
- Integration between frontend and backend
- Accessibility (automated a11y checks)

## Step 4: Systematic edge case discovery

For each component/endpoint, apply these categories:

### Input Edge Cases

| Category | Test Cases |
|---|---|
| **Null/Empty** | null, empty string, empty collection, whitespace only |
| **Boundary** | 0, 1, max-1, max, max+1, negative, MIN_VALUE, MAX_VALUE |
| **Format** | Unicode (日本語), emoji (🎉), special chars (&lt;&gt;&amp;), SQL injection attempts, XSS payloads, very long strings (10K+ chars) |
| **Type** | Wrong type, numeric overflow, invalid enum value, malformed JSON |

### State Edge Cases

| Category | Test Cases |
|---|---|
| **Initial** | First-time use, empty database, no configuration |
| **Concurrent** | Simultaneous updates, double-submit, race conditions |
| **Expired** | Expired tokens, timed-out sessions, stale cache |
| **Corrupt** | Invalid stored state, partial data, orphaned references |

### Environment Edge Cases

| Category | Test Cases |
|---|---|
| **Time** | Timezone differences, DST transitions, leap year, midnight boundary |
| **Network** | Timeout, connection refused, slow response, partial response, DNS failure |
| **Volume** | 0 items, 1 item, 1000 items, pagination boundary, data larger than memory |
| **Permission** | Unauthenticated, wrong role, expired token, cross-tenant access |

## Step 5: Define test data strategy

Choose the appropriate approach:

| Approach | When to Use | Example |
|---|---|---|
| **Builder pattern** | Complex domain objects | `new OrderBuilder().WithItems(3).Build()` |
| **Factory methods** | Simple objects | `TestData.CreateUser(role: "Admin")` |
| **Fixtures** | Shared database state | `DatabaseFixture : IAsyncLifetime` |
| **Inline** | Simple, one-off data | `var name = "Test User";` |
| **External files** | Large datasets, golden files | `testdata/orders.json` |

Rules for test data:
- Tests must not depend on shared mutable state.
- Each test creates its own data or uses a clean fixture.
- Database tests reset state between runs (Respawn, transactions, or recreate).
- Sensitive data must never be used in tests (use synthetic data).

## Step 6: Create test case outlines

For each test, document:

```markdown
### TC-{id}: {Descriptive name}

**Level:** Unit / Integration / E2E
**Component:** {what is being tested}
**Risk:** 🔴/🟠/🟡/🟢
**Scenario:** {Given/When/Then}

Given {precondition}
When {action}
Then {expected outcome}

**Test Data:** {what data is needed}
**Mocks/Stubs:** {what dependencies are mocked}
```

## Step 7: Identify coverage risks and existing signals

If tests already exist, use them only to inform the forward-looking plan:

1. **Review available coverage signals** — line/branch coverage, mutation reports, or known weak areas if already available.
2. **Identify planning risks** — error handling, edge cases, and boundary conditions implementers should prioritize.
3. **Avoid retroactive gap filling** — record the evidence and recommend a
   separate `test-gap-analysis` after this strategy is complete. Do not invoke
   that coordinator inside this skill or silently expand the approved scope.
4. **Review test quality signals** — note weak assertions or brittle patterns as risks, not implementation work for this skill.

---

# Output format

```markdown
# Test Strategy: {Feature/Component}

**Date:** {date}
**Scope:** {what is covered}
**Risk Level:** 🔴/🟠/🟡/🟢

## Risk Assessment

| Component | Risk Level | Rationale |
|---|---|---|
| {component} | 🔴/🟠/🟡/🟢 | {why this risk level} |

## Test Pyramid

| Level | Count | Components Covered |
|---|---|---|
| Unit | ~{N} | {list} |
| Integration | ~{N} | {list} |
| E2E | ~{N} | {list} |

## Test Cases

### Unit Tests

#### TC-01: {Name}
**Component:** {component}
**Given** {precondition}
**When** {action}
**Then** {expected outcome}

#### TC-02: {Name}
...

### Integration Tests

#### TC-10: {Name}
...

### E2E Tests

#### TC-20: {Name}
...

## Edge Cases

| # | Category | Scenario | Expected Behavior | Priority |
|---|---|---|---|---|
| EC-1 | {category} | {scenario} | {behavior} | High/Med/Low |

## Test Data Strategy

{Approach: builders, factories, fixtures}
{Database reset strategy}
{Sensitive data handling}

## Coverage Risks / Existing Signals

| Area | Current Coverage | Gap | Recommendation |
|---|---|---|---|
| {area} | {percentage or description} | {what's missing} | {what to add} |

## Agent Assignments

| Test Area | Responsible Agent |
|---|---|
| Domain unit tests | `implementer` |
| API integration tests | `implementer` |
| Isolated component unit tests | `implementer` with frontend domain input when needed |
| E2E tests | `implementer`, test-only scope |

## Recommendations

1. {Priority 1 — most impactful test to add}
2. {Priority 2}
3. {Priority 3}
```

---

# Example output

## Input

> "Create a test strategy for our user registration feature."

## Output (abbreviated)

```markdown
# Test Strategy: User Registration

**Date:** 2026-04-13
**Scope:** Registration API endpoint, validation, email confirmation, UI form
**Risk Level:** 🔴 Critical (security-sensitive, data integrity)

## Risk Assessment

| Component | Risk | Rationale |
|---|---|---|
| Password hashing | 🔴 Critical | Security: incorrect hashing = data breach |
| Email uniqueness | 🔴 Critical | Data integrity: duplicate accounts |
| Input validation | 🟠 High | Injection, XSS, data quality |
| Email confirmation | 🟠 High | Account takeover if broken |
| Registration form UI | 🟡 Medium | UX but not data risk |

## Test Pyramid

| Level | Count | Components |
|---|---|---|
| Unit | ~15 | Validator, UserEntity, PasswordHasher, RegistrationHandler |
| Integration | ~8 | POST /api/register, email service, database |
| E2E | ~2 | Full registration flow, duplicate email flow |

## Test Cases

### Unit Tests

#### TC-01: Reject registration with password shorter than 12 characters
**Component:** RegistrationValidator
**Given** a registration request with password "short"
**When** validation runs
**Then** validation fails with error "Password must be at least 12 characters"

#### TC-02: Reject registration with duplicate email
**Component:** RegistrationHandler
**Given** a user with email "test@example.com" already exists
**When** a new registration with the same email is submitted
**Then** registration fails with error "Email already in use"

### Edge Cases

| # | Category | Scenario | Expected | Priority |
|---|---|---|---|---|
| EC-1 | Format | Email with unicode (tëst@example.com) | Reject or normalize | High |
| EC-2 | Concurrent | Two registrations with same email simultaneously | Only one succeeds | High |
| EC-3 | Boundary | Password exactly 12 characters | Accept | Medium |
| EC-4 | Injection | Email containing SQL: ' OR 1=1-- | Reject or sanitize | Critical |
```

---

# Agent coordination

| Task | Agent |
|---|---|
| Domain logic unit tests | `implementer` |
| API integration tests | `implementer` |
| Database test setup | `implementer` |
| Isolated Angular/Blazor component unit tests | `implementer` with frontend domain input when needed |
| Frontend integration tests | `implementer` |
| E2E test implementation | `implementer`, test-only scope |
| Security test scenarios | `investigator` |
| Test data strategy | `investigator` |
| Acceptance criteria | `investigator` |
| Usability test planning | `investigator` |

---

## Approval and Handoff

This skill produces a proposed strategy only. Present it to the user for
approval before any agent implements the planned tests. After approval, finish
this planning skill's state and return the bounded assignments to the caller:
approved unit, integration, E2E, performance and cross-pyramid test changes go
to `implementer` with test-only scope. `investigator` supplies analysis, never
test implementation or command execution. These assignments remain terminal;
production defects return to the caller for a separately authorized fix.
If a separate `test-gap-analysis` is requested, start it
only after the current owning workflow ends, with its own approval gate.
The strategy itself is conversational unless the user explicitly asks to persist
it in a repository artifact.

# Checklist

1. ☐ Target code/feature analyzed and understood
2. ☐ Risk levels assigned to each component
3. ☐ Test pyramid designed (unit/integration/E2E allocation)
4. ☐ Edge cases discovered systematically
5. ☐ Test data strategy defined
6. ☐ Test cases outlined with Given/When/Then
7. ☐ Coverage gaps identified (if existing tests)
8. ☐ Agent assignments for test implementation
9. ☐ Strategy reviewed and prioritized

---

# Rules

- Focus testing effort on high-risk areas — don't aim for 100% coverage everywhere.
- Every test must have meaningful assertions — executing code without verifying outcomes is not testing.
- Edge cases are not optional — they're where bugs hide.
- Test data must be independent — no shared mutable state between tests.
- Flaky tests must be called out as risks for the owning implementer.
- Every bug fix should include a regression test in the implementation plan.
- Test the behavior, not the implementation — refactoring should not break tests.
- Present the strategy for review before implementation begins.
- Do not hand planned tests to an implementation agent until the user approves the strategy.

---
