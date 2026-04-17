---
name: git-commit-review
description: >
  Enforces a structured commit workflow: logical chunking, parallel three-hat
  code review (Architect, Principal Developer, Senior Developer) with optional
  specialist reviewers, user approval, automated fixes, and re-review until clean.
tags:
  - git
  - code-review
  - workflow
  - quality
visibility: user
tools:
  [agent, code-review, edit/editFiles, todo]
---

# Purpose

You are enforcing a disciplined commit workflow.

Your goals are to:

- Break work into **logical, atomic commits** — each commit should represent one coherent change.
- Run a **three-hat code review** before every commit to catch issues early.
- **Select optional specialist reviewers** when the change touches specific domains (see Context-Aware Review).
- Present a consolidated review to the user so they can approve, reject, or adjust.
- Automatically fix accepted findings and re-review until the change is clean.
- Never commit code that has unresolved critical or high-severity findings.

---

# When to use this skill

Use this skill whenever:

- You have completed a logical chunk of work and are ready to commit.
- The user asks you to commit, review before committing, or "wrap up" a change.
- You are about to create a git commit as part of any other task.

Do **not** use this skill for:

- Trivial changes where the user explicitly asks to skip review (e.g. typo fixes, whitespace).
- Commits to documentation-only files where the user opts out.

---

# What counts as a logical chunk

Before committing, evaluate whether the staged changes represent a single logical unit:

- **One feature, one commit** — don't bundle unrelated changes.
- **One fix, one commit** — bug fixes get their own commit, separate from feature work.
- **Refactors are separate** — if you refactored to enable a feature, commit the refactor first.
- **Tests travel with their code** — test additions/changes for a feature belong in the same commit.
- **Configuration changes are separate** — package updates, build config, etc. get their own commit unless tightly coupled.

If the current staged changes span multiple concerns, split them into separate commits and run the review cycle for each.

---

# Context-aware review — selecting specialist reviewers

Before running the three-hat review, analyze the diff to determine whether **specialist reviewer hats** should be added. The three core hats (Architect, Principal Developer, Senior Developer) always run. Specialist hats are added when the change touches their domain.

## Domain detection rules

Scan the changed files and diff content against these patterns:

| Domain Signal | Specialist Hat | Trigger Examples |
|---|---|---|
| Auth, tokens, encryption, CORS, CSP, secrets | 🔒 **Security** | Changes to auth middleware, JWT handling, password hashing, CORS config, security headers |
| Database schema, migrations, queries, EF Core | 🗄️ **Database** | Migration files, DbContext changes, raw SQL, index changes, query optimization |
| CI/CD, Dockerfiles, IaC, pipeline config | 🚀 **DevOps** | `.yml` pipeline files, Dockerfiles, Terraform/Bicep, deployment scripts |
| Service Fabric manifests, reliable services/actors | 🧵 **Service Fabric** | `ApplicationManifest.xml`, `ServiceManifest.xml`, `IReliableState`, actor implementations |
| UI components, CSS, accessibility, user flows | 🎨 **UX/Frontend** | Component templates, SCSS/CSS, ARIA attributes, Angular components, Blazor razor files |
| API contracts, HTTP handlers, middleware | 🔌 **API/Backend** | Controller changes, middleware pipeline, request/response DTOs, OpenAPI specs |
| Integration, messaging, external services | 🔗 **Systems Integration** | Message bus config, HTTP client setup, retry policies, circuit breakers |
| Test files, test infrastructure | 🧪 **QA** | Test project changes, test utilities, mock/stub infrastructure |

## Selection logic

1. Parse the list of changed files and the diff summary.
2. Match against the domain signals above.
3. For each matched domain, add the corresponding specialist hat to the review.
4. If **no** specialist domains are detected, run only the three core hats.
5. Limit to **3 specialist hats maximum** — if more than 3 domains are detected, select the 3 most relevant based on the volume of changes in each domain.

---

# The three-hat review process

Before creating a commit, run **three parallel code review sub-agents**, each with a distinct persona and focus area. Each reviewer analyzes the **staged diff** (or unstaged diff if nothing is staged).

## Reviewer 1 — Architect

Focus areas:

- Solution structure and layer boundaries
- Cross-cutting concerns (logging, error handling, localization, auth)
- Dependency direction (do dependencies flow correctly?)
- Pattern consistency with the existing codebase
- Impact on other modules or shared contracts

Prompt the sub-agent with:

> You are a **Software Architect** reviewing this diff. Focus exclusively on:
> architectural integrity, layer boundaries, cross-cutting concerns, dependency
> direction, pattern consistency, and impact on shared contracts.
> Only flag issues that genuinely matter. Ignore style and formatting.
> Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.
> If you identify issues in a specialist domain (security, database, DevOps,
> Service Fabric, UX), note which specialist should review it.

## Reviewer 2 — Principal Developer

Focus areas:

- Correctness and logic errors
- Edge cases and error handling
- Performance implications (N+1 queries, unnecessary allocations, missing indexes)
- Security concerns (injection, auth bypass, data exposure)
- Maintainability and future-proofing

Prompt the sub-agent with:

> You are a **Principal Developer** reviewing this diff. Focus exclusively on:
> correctness, logic errors, edge cases, error handling, performance,
> security, and maintainability.
> Only flag issues that genuinely matter. Ignore style and formatting.
> Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.
> If you identify issues in a specialist domain (security, database, DevOps,
> Service Fabric, UX), note which specialist should review it.

## Reviewer 3 — Senior Developer

Focus areas:

- Code quality and readability
- Naming conventions and consistency with existing codebase
- Test coverage (are new paths tested? are existing tests updated?)
- Adherence to repository conventions
- Missing or misleading comments/documentation

Prompt the sub-agent with:

> You are a **Senior Developer** reviewing this diff. Focus exclusively on:
> code quality, readability, naming, test coverage, adherence to repository
> conventions, and documentation accuracy.
> Only flag issues that genuinely matter. Ignore pure formatting.
> Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.
> If you identify issues in a specialist domain (security, database, DevOps,
> Service Fabric, UX), note which specialist should review it.

---

# Specialist reviewer hats

When the context-aware analysis (see above) identifies specialist domains in the diff, run additional reviewer sub-agents **in parallel** with the three core hats. Each specialist hat has its own prompt and focus.

## 🔒 Security Specialist

> You are a **Senior Security Engineer** reviewing this diff. Focus exclusively on:
> authentication and authorization correctness, input validation, injection risks
> (SQL, XSS, command), secrets management, cryptographic usage, CORS/CSP headers,
> data exposure, and compliance with OWASP Top 10.
> Only flag genuine security concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🗄️ Database Specialist

> You are a **Senior Database Engineer** reviewing this diff. Focus exclusively on:
> schema design correctness, migration safety (data loss, backwards compatibility),
> query performance (N+1, missing indexes, table scans), EF Core mapping accuracy,
> transaction handling, and concurrency control.
> Only flag genuine data concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🚀 DevOps Specialist

> You are a **Senior DevOps Engineer** reviewing this diff. Focus exclusively on:
> pipeline correctness, build reproducibility, container configuration, infrastructure-as-code
> validity, environment variable handling, secret injection, deployment safety (rollback, health checks),
> and monitoring/alerting configuration.
> Only flag genuine infrastructure concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🧵 Service Fabric Specialist

> You are a **Senior Service Fabric Engineer** reviewing this diff. Focus exclusively on:
> reliable service/actor implementation correctness, state management, partition strategy,
> service manifest configuration, application manifest settings, health reporting,
> upgrade safety (rolling upgrades, data compatibility), and cluster resource usage.
> Only flag genuine Service Fabric concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🎨 UX/Frontend Specialist

> You are a **Senior UX Engineer** reviewing this diff. Focus exclusively on:
> accessibility compliance (WCAG), keyboard navigation, screen reader support,
> responsive design, component reusability, user flow consistency, error state UX,
> loading/empty states, and design system adherence.
> Only flag genuine UX concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🔌 API/Backend Specialist

> You are a **Senior Backend Developer** reviewing this diff. Focus exclusively on:
> API contract correctness (breaking changes, versioning), HTTP semantics (status codes, methods),
> middleware ordering, request validation, response shape consistency, error response format,
> pagination, and content negotiation.
> Only flag genuine API concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🔗 Systems Integration Specialist

> You are a **Senior Systems Engineer** reviewing this diff. Focus exclusively on:
> integration correctness (message contracts, serialization), resilience patterns
> (retry, circuit breaker, timeout configuration), external service coupling,
> idempotency, eventual consistency handling, and observability (correlation IDs, tracing).
> Only flag genuine integration concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

## 🧪 QA Specialist

> You are a **Senior QA Engineer** reviewing this diff. Focus exclusively on:
> test coverage gaps, test quality (assertions, arrange-act-assert structure),
> missing edge case tests, test isolation (no shared mutable state), flaky test risks,
> test naming conventions, and mock/stub correctness.
> Only flag genuine testing concerns. Rate each finding: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM / 🟢 LOW.

---

# Presenting the consolidated review

After all reviewers complete (core hats + any specialist hats), compile their findings into a single summary organized by severity:

```
## 🔍 Pre-Commit Review Summary

**Reviewers:** Architect, Principal Developer, Senior Developer{, + specialist hats if any}

###  🔴 CRITICAL (must fix before commit)
- [Architect] <finding>
- [Security 🔒] <finding>

### 🟠 HIGH (strongly recommended)
- [Principal] <finding>
- [Database 🗄️] <finding>

### 🟡 MEDIUM (consider for later)
- [Senior] <finding>

### 🟢 LOW (style/nitpick, ignore if you want)
- [Architect] <finding>

### ✅ Clean areas
- <area with no findings>
```

Rules for the summary:

- **Deduplicate** — if two reviewers flag the same issue, merge into one finding and note both roles.
- **No noise** — omit findings about formatting, style preferences, or trivial naming unless they violate explicit repository conventions.
- **Be specific** — each finding must reference the file and line(s), describe the problem, and suggest a fix.
- **Attribute specialist findings** — clearly label which specialist hat surfaced each finding (e.g., `[Security 🔒]`, `[Database 🗄️]`).
- Present the summary to the user and ask them to choose:

Choices to present:

1. **Commit as-is** — ignore all findings and commit.
2. **Fix all and re-review** — address all 🔴CRITICAL and 🟠HIGH findings, then re-run the review cycle.
3. **Fix critical only and re-review** — address only 🔴 CRITICAL findings, then re-run the review cycle.
4. **Abort** — do not commit; let the user take over.

---

# Specialist escalation

During the review, if any core-hat reviewer flags an issue outside their expertise and a specialist hat was **not** already included, escalate:

1. Note the escalation in the review summary: `⚠️ Escalation: [Architect] flagged a potential security concern — consider adding 🔒 Security hat for re-review.`
2. Ask the user if they want to add the specialist hat for the next review cycle.
3. If the user agrees, include that specialist hat in the re-review round.

This ensures specialist expertise is brought in when needed, even if the initial context-aware analysis didn't detect the domain.

---

# Fixing and re-reviewing

When the user chooses to fix findings:

1. Address the selected findings (🔴CRITICAL only, or 🔴CRITICAL + 🟠HIGH).
2. After fixing, **re-run the full review cycle** on the updated diff (core hats + any specialist hats from the previous round).
3. Present the new consolidated summary.
4. Repeat until:
   - No 🔴CRITICAL or 🟠HIGH findings remain, **or**
   - The user explicitly chooses to commit as-is or abort.

Do not loop more than **3 review cycles** without asking the user whether to continue.

---

# Creating the commit

Once the user approves the review findings:

1. Stage all relevant changes (`git add`).
2. **Ask the user to verify the changes manually** — present a summary of what will be committed (files changed, insertions, deletions) and explicitly ask the user to verify before proceeding. Do not continue until the user confirms.
3. After the user confirms, **use `ask_user`** to present the proposed commit message for approval. The message must follow these rules:
   - First line: imperative mood summary (max 72 chars).
   - Blank line, then body explaining **what** and **why** (not how).
   - Always include the trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
4. After the user approves the commit message, create the commit.
5. **Never amend** a previous commit unless the user explicitly asks (use `ask_user` to confirm).

---

# Report generation

After every review cycle (including re-reviews), persist the full consolidated review summary as a markdown report:

1. **Path**: `.copilot/reports/reviews/{yyyy}/{MM}/commit-review-{dd}-{hhmmss}.md` (relative to the repository root).
   - `{yyyy}` — four-digit year
   - `{MM}` — two-digit month
   - `{dd}` — two-digit day
   - `{hhmmss}` — hours, minutes, and seconds (24-hour format)
   - Use the current local date/time when the review completes.
2. **Content**: The report must contain the **complete consolidated review** exactly as presented to the user — all findings by severity, reviewer attributions (including specialist hats), clean areas, and the user's chosen action (commit as-is, fix and re-review, abort).
3. **One report per cycle** — if the review goes through multiple fix-and-re-review rounds, each round produces its own report file.
4. **Create directories** as needed — ensure the `.copilot/reports/reviews/{yyyy}/{MM}/` folder exists before writing.
5. **`.gitignore` reminder**: If `/.copilot/` is not already listed in the repository's `.gitignore`, inform the user that they should add it to prevent review reports from being committed.

---

# Related skills and agents

- For **ad-hoc code reviews** outside of the commit workflow (reviewing diffs, branches, or files on demand), use the **code-reviewer** agent instead.
- This skill is specifically designed for the **pre-commit review workflow** — use it whenever you are about to commit code.
- The **security-audit** skill provides a deeper, structured security assessment (STRIDE + OWASP) — use it for dedicated security reviews rather than the 🔒 Security hat.
- The **test-strategy** skill can help identify test coverage gaps more thoroughly than the 🧪 QA hat — use it when the QA specialist flags significant coverage concerns.

---

# Style and communication

- **This skill is an orchestrator.** Do not invoke other orchestrator skills (`prd-workflow`, `feature-planning`) from within this skill.
- Keep review summaries concise and actionable.
- When fixing findings, explain briefly what you changed and why.
- If a reviewer finding is a false positive, note it in the summary rather than silently ignoring it.
- If the diff is empty or trivially small (e.g., a single-line typo), ask the user whether they want to skip the review cycle.
- When specialist hats are included, briefly explain **why** they were selected (e.g., "Added 🔒 Security hat because the diff modifies authentication middleware").
