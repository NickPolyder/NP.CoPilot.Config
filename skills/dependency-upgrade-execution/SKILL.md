---
name: dependency-upgrade-execution
description: >
  Executes an approved dependency upgrade plan in risk-ordered batches
  (patch → minor → major) with restore/build/test verification after each batch,
  then hands verified changes to git-commit-review.
tags:
  - dependencies
  - upgrade
  - execution
  - maintenance
visibility: user
tools:
  [agent, edit/editFiles]
---

# Purpose

> **Intent (anchor):** Execute an approved dependency upgrade plan in risk-ordered batches with verification after each batch, then prepare commit handoff.
> **Always:** require explicit approval before editing manifests; upgrade patch, minor, then major versions; verify restore, build, and tests after each batch.
> **Never:** upgrade blindly, start without an approved scope, stack upgrades on a broken build, mix with feature work, or create commits directly.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

You are executing an approved dependency upgrade plan. This skill edits manifests only after an explicit approval gate and verifies restore, build, and tests after each batch.

Your goals are to:

- **Execute approved upgrades** — apply only the dependency changes the user approved.
- **Minimize upgrade risk** — batch patch updates, group related minor updates, and handle major updates one at a time.
- **Verify continuously** — restore, build, and test after each batch before continuing.
- **Hand off cleanly** — provide verified package changes, lock file changes, test results, and skipped follow-ups to `git-commit-review`.

---

# When to use this skill

Use this skill whenever:

- The user approved a `dependency-audit-report` upgrade plan and wants the changes applied.
- The user explicitly chooses one of the upgrade options from the audit hand-off prompt.
- A specific CVE fix version has been identified and the user approves applying it.
- You need the second step in the chain: `dependency-audit-report` → explicit approval → `dependency-upgrade-execution`.

Do **not** use this skill for:

- Read-only dependency discovery, risk assessment, or reporting — use `dependency-audit-report`.
- Adding new dependencies — just add them directly.
- Debugging dependency conflicts during development — investigate directly.
- Framework upgrades (e.g., .NET 8 → .NET 9) — those are architectural changes requiring the Full tier workflow.
- Commit review or commit creation — hand verified changes to `git-commit-review`.

---

# Workflow

## Approval Gate (required)

Before editing manifests or lock files, confirm the user has explicitly chosen an upgrade option from the audit hand-off:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

Proceed only when the user explicitly approves an upgrade scope. If the user chooses option 4 or does not approve edits, stop without changing manifests.

## Phase 3: Upgrade Execution (approval required)

Only enter this phase after explicit user approval to edit dependency manifests. Upgrade in batches, ordered by risk (lowest risk first):

### Batch Strategy

1. **Patch updates** — all at once (low risk, no breaking changes).
2. **Minor updates** — group by related packages (e.g., all Microsoft.Extensions.* together).
3. **Major updates** — one at a time (highest risk, most likely to break).

### For each batch:

1. **Update package references** — modify .csproj / package.json.
2. **Restore** — `dotnet restore` / `npm install`.
3. **Build** — verify compilation.
4. **Test** — run full test suite.
5. **If tests fail:**
   - Identify which upgrade caused the failure.
   - Check migration guides for the breaking package.
   - Apply necessary code changes.
   - Re-test.
   - If unfixable quickly, revert that package and note it as a follow-up.

### After all batches:

```
### Upgrade Summary

**Upgraded:** {N} packages
**Skipped:** {N} packages (reason: {breaking changes needing deeper work})
**Tests:** {passed}/{total} passing
**Build:** ✅ Clean

Remaining work (if any):
- {Package X} requires code migration — see {link to migration guide}
```

## Vulnerability-Specific Mode (upgrade/verify/document)

When responding to a specific CVE or security advisory after approval:

4. **Upgrade** — update to the fix version (not necessarily latest, to minimize risk).
5. **Verify** — build + test.
6. **Document** — include the CVE and fix in the upgrade summary for the `git-commit-review` handoff.

## Phase 4: Commit Handoff

Do not define or create commits here. After approved upgrade batches build and tests pass, recommend delegating commit review and commit creation to the `git-commit-review` skill. Provide it the package changes, lock file changes, verification results, and any skipped follow-ups.

---

# Coordination

- **Consult `security-engineer`** — for CVE impact assessment and exposure analysis.
- **Consult `backend-developer`** — for .NET-specific migration patterns when major packages change.
- **Consult `frontend-developer`** — for Angular/npm ecosystem upgrade patterns.
- **Consult `devops-engineer`** — if dependency updates affect Docker images or CI pipelines.
- **Delegate commits to `git-commit-review`** — provide verified package changes, lock file changes, verification results, and skipped follow-ups; never invoke it from this skill.

---

# Constraints

- **Explicit approval required** — do not change manifests or lock files until an upgrade scope is approved.
- **Never upgrade blindly** — always check for breaking changes before updating a major version.
- **Tests must pass after each batch** — don't stack upgrades on a broken build.
- **Respect lock files** — commit updated lock files alongside package reference changes.
- **Don't mix dependency upgrades with feature work** — keep dependency changes separate from feature work.
- **Delegate commits** — hand verified upgrade batches to `git-commit-review`; this skill does not own commit strategy.
- **Atomic skill** — execute approved upgrades and prepare the hand-off only.
- **Not an orchestrator** — consult specialist agents only for domain expertise and never invoke another skill.

---

## Final Rules (Anchor)

1. Do not edit manifests or lock files until explicit approval confirms the exact upgrade scope.
2. Upgrade in risk-ordered batches: patch, minor, major; verify restore, build, and tests after each batch.
3. Never stack upgrades on a broken build; fix, revert, or mark skipped before continuing.
4. Delegate commit review and commit creation to `git-commit-review`; do not create commits here.
> If anything above conflicts with these, **these win**.
