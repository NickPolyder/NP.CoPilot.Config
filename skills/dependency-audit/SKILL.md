---
name: dependency-audit
description: >
  Audits project dependencies for outdated versions, known vulnerabilities,
  and license risks. Proposes a safe, incremental upgrade path with test
  verification at each step.
tags:
  - dependencies
  - security
  - maintenance
  - nuget
  - npm
visibility: user
tools:
  [agent, edit/editFiles]
---

# Purpose

You are conducting a dependency health audit and safe upgrade process.

Your goals are to:

- **Identify outdated packages** — find dependencies behind current stable versions.
- **Surface vulnerabilities** — check for known CVEs and security advisories.
- **Assess upgrade risk** — categorize each update by breaking-change potential.
- **Execute safe upgrades** — update incrementally with test verification after each batch.

---

# When to use this skill

Use this skill whenever:

- The user asks to "update dependencies", "check for vulnerabilities", or "audit packages".
- Starting a new sprint or maintenance cycle — periodic dependency hygiene.
- A security advisory is reported and you need to assess impact.
- Before a major release — ensure dependencies are current and secure.

Do **not** use this skill for:

- Adding new dependencies — just add them directly.
- Debugging dependency conflicts during development — investigate directly.
- Framework upgrades (e.g., .NET 8 → .NET 9) — those are architectural changes requiring the Full tier workflow.

---

# Workflow

## Phase 1: Discovery

Scan the project for dependency manifests and current state:

### .NET Projects

```powershell
dotnet list package --outdated
dotnet list package --vulnerable
dotnet list package --deprecated
```

### Node.js Projects

```powershell
npm outdated
npm audit
```

### Both

- Check for lock file freshness (packages.lock.json, package-lock.json).
- Identify transitive dependency risks.

## Phase 2: Risk Assessment

Categorize each outdated/vulnerable dependency:

| Category | Criteria | Action |
|----------|----------|--------|
| 🔴 **Critical** | Known CVE with exploit, actively targeted | Upgrade immediately |
| 🟠 **High** | Known vulnerability, deprecated package, or 2+ major versions behind | Upgrade this cycle |
| 🟡 **Medium** | Minor version behind, non-security fixes available | Upgrade when convenient |
| 🟢 **Low** | Patch version behind, cosmetic/perf improvements only | Batch with other upgrades |

Present a summary table:

```
### Dependency Audit Results

| Package | Current | Latest | Category | Breaking Changes? | Notes |
|---------|---------|--------|----------|-------------------|-------|
| Newtonsoft.Json | 13.0.1 | 13.0.3 | 🟢 Low | No | Patch fixes |
| FluentValidation | 10.x | 11.x | 🟡 Medium | Yes — API changes | Migration guide available |
| System.Text.Json | 7.0.0 | 9.0.0 | 🟠 High | Yes — .NET version tied | Requires TFM update |

**Summary:** {N} packages reviewed, {critical} critical, {high} high priority
```

Ask:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

## Phase 3: Upgrade Execution

Upgrade in batches, ordered by risk (lowest risk first):

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

## Phase 4: Commit

- **Patch updates:** One commit ("chore: update patch dependencies").
- **Minor updates:** One commit per logical group ("chore: update Microsoft.Extensions to 9.x").
- **Major updates:** One commit per package ("chore: upgrade FluentValidation to 11.x").

Each commit must build and pass tests independently.

---

# Vulnerability-Specific Mode

When responding to a specific CVE or security advisory:

1. **Identify affected packages** — which dependencies in this project are impacted?
2. **Assess exposure** — is the vulnerable code path actually reachable in this project?
3. **Find the fix version** — what's the minimum version that patches the vulnerability?
4. **Upgrade** — update to the fix version (not necessarily latest, to minimize risk).
5. **Verify** — build + test.
6. **Document** — note the CVE and fix in the commit message.

---

# Coordination

- **Consult `security-engineer`** — for CVE impact assessment and exposure analysis.
- **Consult `backend-developer`** — for .NET-specific migration patterns when major packages change.
- **Consult `frontend-developer`** — for Angular/npm ecosystem upgrade patterns.
- **Consult `devops-engineer`** — if dependency updates affect Docker images or CI pipelines.

---

# Constraints

- **Never upgrade blindly** — always check for breaking changes before updating a major version.
- **Tests must pass after each batch** — don't stack upgrades on a broken build.
- **Respect lock files** — commit updated lock files alongside package reference changes.
- **Don't mix dependency upgrades with feature work** — keep upgrade commits separate.
- **This skill is not an orchestrator** — it follows the Standard tier workflow for commits.
