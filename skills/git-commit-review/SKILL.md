---
name: git-commit-review
description: >
  Enforces a structured commit workflow: logical chunking, parallel three-hat
  code review (Architect, Principal Developer, Senior Developer), user approval,
  automated fixes, and re-review until clean.
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

---

# Presenting the consolidated review

After all three reviewers complete, compile their findings into a single summary organized by severity:

```
## 🔍 Pre-Commit Review Summary

###  🔴 CRITICAL (must fix before commit)
- [Architect] <finding>
- [Principal] <finding>
- [Senior] <finding>

### 🟠 HIGH (strongly recommended)
- [Architect] <finding>
- [Principal] <finding>
- [Senior] <finding>

### 🟡 MEDIUM (consider for later)
- [Architect] <finding>
- [Principal] <finding>
- [Senior] <finding>

### 🟢 LOW (style/nitpick, ignore if you want)
- [Architect] <finding>
- [Principal] <finding>
- [Senior] <finding>

### ✅ Clean areas
- <area with no findings>
```

Rules for the summary:

- **Deduplicate** — if two reviewers flag the same issue, merge into one finding and note both roles.
- **No noise** — omit findings about formatting, style preferences, or trivial naming unless they violate explicit repository conventions.
- **Be specific** — each finding must reference the file and line(s), describe the problem, and suggest a fix.
- Present the summary to the user and ask them to choose:

Choices to present:

1. **Commit as-is** — ignore all findings and commit.
2. **Fix all and re-review** — address all 🔴CRITICAL and 🟠HIGH findings, then re-run the review cycle.
3. **Fix critical only and re-review** — address only 🔴 CRITICAL findings, then re-run the review cycle.
4. **Abort** — do not commit; let the user take over.

---

# Fixing and re-reviewing

When the user chooses to fix findings:

1. Address the selected findings (🔴CRITICAL only, or 🔴CRITICAL + 🟠HIGH).
2. After fixing, **re-run the full three-hat review cycle** on the updated diff.
3. Present the new consolidated summary.
4. Repeat until:
   - No 🔴CRITICAL or 🟠HIGH findings remain, **or**
   - The user explicitly chooses to commit as-is or abort.

Do not loop more than **3 review cycles** without asking the user whether to continue.

---

# Creating the commit

Once the user approves:

1. Stage all relevant changes (`git add`).
2. Write a clear, conventional commit message:
   - First line: imperative mood summary (max 72 chars).
   - Blank line, then body explaining **what** and **why** (not how).
   - Always include the trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
3. Create the commit.
4. **Never amend** a previous commit unless the user explicitly asks.

---

# Report generation

After every review cycle (including re-reviews), persist the full consolidated review summary as a markdown report:

1. **Path**: `.copilot/reports/reviews/{yyyy}/{MM}/code-review-{dd}-{hhmmss}.md` (relative to the repository root).
   - `{yyyy}` — four-digit year
   - `{MM}` — two-digit month
   - `{dd}` — two-digit day
   - `{hhmmss}` — hours, minutes, and seconds (24-hour format)
   - Use the current local date/time when the review completes.
2. **Content**: The report must contain the **complete consolidated review** exactly as presented to the user — all findings by severity, reviewer attributions, clean areas, and the user's chosen action (commit as-is, fix and re-review, abort).
3. **One report per cycle** — if the review goes through multiple fix-and-re-review rounds, each round produces its own report file.
4. **Create directories** as needed — ensure the `.copilot/reports/reviews/{yyyy}/{MM}/` folder exists before writing.
5. **`.gitignore` reminder**: If `/.copilot/` is not already listed in the repository's `.gitignore`, inform the user that they should add it to prevent review reports from being committed.

---

# Related

- For **ad-hoc code reviews** outside of the commit workflow (reviewing diffs, branches, or files on demand), use the **code-reviewer** agent instead.
- This skill is specifically designed for the **pre-commit review workflow** — use it whenever you are about to commit code.

---

# Style and communication

- Keep review summaries concise and actionable.
- When fixing findings, explain briefly what you changed and why.
- If a reviewer finding is a false positive, note it in the summary rather than silently ignoring it.
- If the diff is empty or trivially small (e.g., a single-line typo), ask the user whether they want to skip the review cycle.
