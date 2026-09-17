---
name: dependency-upgrade-execution
description: >
  Executes an approved dependency upgrade plan in risk-ordered batches
  (patch → minor → major) with restore/build/test verification after each batch,
  then hands verified changes to git-commit-review.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

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
- Framework upgrades (e.g., .NET 8 → .NET 9) — those require explicit architectural scope and approval.
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
Carry the approved report's license evidence, declared policy, required
obligations, and unresolved decisions into execution. Upgrade approval is not a
license-policy waiver or permission to remove/replace unrelated dependencies.

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
5. **Recheck dependency/license evidence** — record the resulting direct and
   transitive versions and their version-specific licenses against the approved
   policy constraints. Follow the evidence/output contract in
   `dependency-audit-report` without invoking another workflow. Preserve unknown
   or not-assessed states and stop on unresolved required policy decisions;
   successful tests do not resolve a license conflict.
6. **If tests fail:**
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
**License/policy evidence:** {assessed versions, remaining conflicts/unknowns, required decisions}

Remaining work (if any):
- {Package X} requires code migration — see {link to migration guide}
```

## Vulnerability-Specific Mode (upgrade/verify/document)

When responding to a specific CVE or security advisory after approval:

4. **Upgrade** — update to the fix version (not necessarily latest, to minimize risk).
5. **Verify** — build + test.
6. **Document** — include the CVE and fix in the upgrade summary for the `git-commit-review` handoff.

## Phase 4: Commit Handoff

Do not define or create commits here. Return package/lock-file changes,
revision-bound verification, license-policy evidence, and skipped follow-ups.
When invoked by `dependency-audit`, return to that coordinator; a completed
upgrade phase does not end its parent. Standalone, finish this skill's state
before recommending a separate `git-commit-review` workflow with its own gates.

---

# Coordination

- Keep small approved batches inline; use `implementer` for substantial bounded
  package, lockfile, container or pipeline changes. Use `investigator` only for
  unresolved exposure, license or migration questions that need separate research.
- **Prepare separate commit handoff** — return verified changes, license-policy
  evidence, and follow-ups to the caller; `git-commit-review` starts only after
  the owning workflow completes.

---

# Constraints

- **Explicit approval required** — do not change manifests or lock files until an upgrade scope is approved.
- **Never upgrade blindly** — always check for breaking changes before updating a major version.
- **Tests must pass after each batch** — don't stack upgrades on a broken build.
- **Respect lock files** — commit updated lock files alongside package reference changes.
- **Don't mix dependency upgrades with feature work** — keep dependency changes separate from feature work.
- **Separate delivery** — never invoke a terminal workflow inside this phase or
  its active coordinator; return the handoff evidence first.

---
