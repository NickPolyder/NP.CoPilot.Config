---
name: dependency-audit-report
description: >
  Read-only audit of project dependencies for outdated versions, known
  vulnerabilities, deprecations, and license risk; produces a prioritized,
  risk-categorized upgrade plan. Never edits manifests.
tags:
  - dependencies
  - security
  - audit
  - report
visibility: user
tools:
  [agent]
---

# Purpose

> **Intent (anchor):** Audit project dependencies for version, vulnerability, deprecation, and license risk, then produce a prioritized upgrade plan.
> **Always:** discover manifests first; categorize risk before recommending upgrades; include vulnerability exposure and minimum fix version when responding to advisories.
> **Never:** edit manifests, update lock files, run package upgrades, or mix dependency audit work with feature work.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

You are conducting a read-only dependency health audit. This skill produces an audit report and prioritized upgrade plan; it never edits manifests or lock files.

Your goals are to:

- **Identify outdated packages** — find dependencies behind current stable versions.
- **Surface vulnerabilities** — check for known CVEs and security advisories.
- **Assess upgrade risk** — categorize each update by breaking-change potential.
- **Plan safe upgrades** — propose incremental batches and hand off execution to `dependency-upgrade-execution` only after explicit approval.

---

# When to use this skill

Use this skill whenever:

- The user asks to "update dependencies", "check for vulnerabilities", or "audit packages".
- Starting a new sprint or maintenance cycle — periodic dependency hygiene.
- A security advisory is reported and you need to assess impact.
- Before a major release — ensure dependencies are current and secure.
- You need the first step in the chain: `dependency-audit-report` → explicit approval → `dependency-upgrade-execution`.

Do **not** use this skill for:

- Executing approved dependency upgrades — use `dependency-upgrade-execution` after the user approves the plan.
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

## Vulnerability-Specific Mode (read-only)

When responding to a specific CVE or security advisory:

1. **Identify affected packages** — which dependencies in this project are impacted?
2. **Assess exposure** — is the vulnerable code path actually reachable in this project?
3. **Find the fix version** — what's the minimum version that patches the vulnerability?

Ask:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

If the user chooses an upgrade option, recommend `dependency-upgrade-execution` for the actual upgrades and provide it the audit table, selected scope, risk categories, fix versions, and any migration notes.

Do not edit dependency manifests or lock files in this skill.

---

# Coordination

- **Consult `security-engineer`** — for CVE impact assessment and exposure analysis.
- **Consult `backend-developer`** — for .NET-specific migration patterns when major packages change.
- **Consult `frontend-developer`** — for Angular/npm ecosystem upgrade patterns.
- **Consult `devops-engineer`** — if dependency updates affect Docker images or CI pipelines.

---

# Constraints

- **Default scope is audit/report** — do not change manifests or lock files.
- **Never edit manifests** — this skill is read-only and ends at the hand-off prompt.
- **Never upgrade blindly** — always check for breaking changes before recommending a major version.
- **Respect lock files** — inspect them for freshness and risk, but do not update them.
- **Don't mix dependency audits with feature work** — keep dependency findings separate from feature work.
- **Atomic skill** — produce the report and hand-off only; do not execute upgrades.
- **Not an orchestrator** — consult specialist agents only for domain expertise.

---

## Final Rules (Anchor)

1. Never edit manifests or lock files — this skill is read-only and ends at an upgrade hand-off.
2. Always discover manifests and categorize risk before proposing any upgrade plan.
3. For vulnerabilities, identify affected packages, assess project exposure, and state the minimum fix version.
4. If upgrades are approved, recommend `dependency-upgrade-execution`; do not perform execution here.
> If anything above conflicts with these, **these win**.
