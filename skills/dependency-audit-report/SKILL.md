---
name: dependency-audit-report
description: >
  Read-only audit of project dependencies for outdated versions, known
  vulnerabilities, deprecations, and license risk; produces a prioritized,
  risk-categorized upgrade plan. Never edits manifests.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

The audit report is conversational by default. Persist it only when the user,
repository policy, or a parent workflow explicitly requests a durable artifact;
otherwise return the findings and proposed upgrade plan without writing files.

You are conducting a read-only dependency health audit. This skill produces an audit report and prioritized upgrade plan; it never edits manifests or lock files.

Your goals are to:

- **Identify outdated packages** — find dependencies behind current stable versions.
- **Surface vulnerabilities** — check for known CVEs and security advisories.
- **Assess licenses** — identify licenses for all direct and transitive
  dependencies and compare them with declared policy, without inventing legal
  approval or treating unknown evidence as clean.
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
- Framework upgrades (e.g., .NET 8 → .NET 9) — those require explicit architectural scope and approval.

---

# Workflow

## Phase 1: Discovery

Scan the target repository's manifests, lock files, workspace/project files, and
declared dependency/license policy. Record the revision and each command's
working directory. Include resolved direct **and transitive** dependencies across
runtime, development, build, and test scopes; state any agreed exclusions.

Prefer existing lock files, resolved graphs, package metadata, and repository
reports. Package-manager queries must be supported by the installed toolchain
and must not restore/install packages or rewrite manifests/lock files. If a
query would do so, use available read-only evidence and report the missing
assessment rather than running it or installing a scanner.

### .NET Projects (read-only queries where supported)

```powershell
dotnet list package --outdated --include-transitive
dotnet list package --vulnerable --include-transitive
dotnet list package --deprecated --include-transitive
```

### Node.js Projects

```powershell
npm outdated
npm audit
```

### Graph and License Evidence

- Check lock-file freshness without updating it. Deduplicate by ecosystem,
  package identity, and exact resolved version, retaining direct/transitive
  classification, introducing dependency paths, and affected projects/scopes.
- For each package/version, identify its declared license expression and evidence:
  package metadata (`license`, NuGet license expression/file, etc.), included
  LICENSE/NOTICE files, or authoritative version-specific upstream metadata.
  Cite the file/path or URL and version; distinguish fetched metadata from
  inspected package contents. An upstream default branch is not proof for a
  different released version.
- Preserve compound `AND`/`OR` expressions, `WITH` exceptions, and custom
  `LicenseRef` terms. Do not replace a dual-license choice or unresolved custom
  text with a guessed permissive license. Disagreement, missing license text, or
  an unresolved transitive graph is an explicit evidence gap.
- Read the repository/organization's declared license rules and intended use
  (distribution, linking, hosted-only use, required notices/source obligations).
  Cite the policy owner/path/rule. The repository's own LICENSE is not by itself
  an allowlist for dependencies. When policy or use context is absent, identify
  available licenses but mark policy compatibility **not assessed**.

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

## Phase 3: License Assessment (independent of version/CVE status)

Assess **every inventoried package/version**, not only outdated or vulnerable
ones, against the declared policy and use context:

| Status | Required meaning |
|---|---|
| **Allowed by declared policy** | Version-specific license evidence satisfies the cited rule and all currently required obligations; cite fulfillment evidence and note ongoing/future obligations. This is not independent legal certification. |
| **Policy conflict** | Evidence conflicts with a specific declared rule or an unmet required obligation; cite both. An up-to-date, vulnerability-free package still appears here. |
| **Unknown** | License identity, version evidence, custom terms, or relevant dependency data is missing, conflicting, or ambiguous. |
| **Not assessed** | License evidence may exist, but policy/use context or a required assessment is unavailable or explicitly out of scope. State why. |

Always include this output, even when no upgrades or vulnerabilities were found:

```markdown
### License Assessment

**Policy and use:** {source/rules + distribution/use context, or absent}
**Inventory:** {revision; projects/scopes; direct/transitive counts; exclusions}
**Coverage:** {resolved graph evidence; missing scopes/unknown total if graph is incomplete}

| Package@resolved version / ecosystem | Direct/transitive; introducer; scope | License expression | Version-specific source evidence | Policy rule and obligations | Status | Required action |
|---|---|---|---|---|---|---|
| {package} | {classification/path} | {expression or unknown} | {path/URL + version} | {rule or absent; obligations/evidence} | {status} | {remediation, decision, or missing input} |

**Totals:** {allowed}, {conflicts}, {unknown}, {not assessed}; {unresolved graph gaps}
```

Include a row for every inventoried package/version or reference a complete
caller-readable inventory with the same fields. Summaries must not hide current
packages or transitives. Unknown/not-assessed entries and missing graph scopes
prevent an unqualified "license clean/compliant" conclusion.

Separate license remediation from upgrade batches. Removal, replacement, choice
of a license option, fulfillment of obligations, or a policy-owner decision may
be needed even when no newer version exists. Report that need without silently
changing policy or treating approval to upgrade as acceptance of license risk.

## Vulnerability-Specific Mode (read-only)

When responding to a specific CVE or security advisory:

1. **Identify affected packages** — which dependencies in this project are impacted?
2. **Assess exposure** — is the vulnerable code path actually reachable in this project?
3. **Find the fix version** — what's the minimum version that patches the vulnerability?

## Audit Completion and Handoff

After the version, vulnerability, and license sections are complete (including
explicit evidence gaps), ask:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

If the user chooses an upgrade option, return the audit table, selected scope,
risk categories, fix versions, migration notes, license evidence/policy
constraints, and unresolved decisions. In a `dependency-audit` phase, return to
that coordinator for its approval gate. Standalone, finish this report phase and
recommend `dependency-upgrade-execution` as a separate approved action.

Do not edit dependency manifests or lock files in this skill.

---

# Coordination

- Use `investigator` only for substantial unresolved CVE exposure, license,
  ecosystem migration or infrastructure questions. Supply relevant domain notes
  and caller-executed command evidence; this remains an audit, not an upgrade.

---

# Constraints

- **Default scope is audit/report** — do not change manifests or lock files.
- **Never edit manifests** — this skill is read-only and ends at the hand-off prompt.
- **Never upgrade blindly** — always check for breaking changes before recommending a major version.
- **Respect lock files** — inspect them for freshness and risk, but do not update them.
- **Don't mix dependency audits with feature work** — keep dependency findings separate from feature work.

---
