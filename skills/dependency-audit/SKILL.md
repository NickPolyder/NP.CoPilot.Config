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

> **Intent (anchor):** Coordinate a two-phase dependency workflow — audit first, then optionally upgrade — by sequencing the atomic `dependency-audit-report` and `dependency-upgrade-execution` skills behind an approval gate.
> **Always:** run the audit (read-only) before any change; require explicit approval before upgrading; keep audit and upgrade as separate atomic steps.
> **Never:** upgrade blindly, skip the approval gate, or mix dependency upgrades with feature work.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

This skill is a **thin coordinator**. It owns the end-to-end dependency-hygiene flow and the gate between audit and upgrade, but delegates the detailed procedures to two atomic skills:

- **`dependency-audit-report`** — read-only discovery, vulnerability/risk assessment, and a prioritized upgrade plan.
- **`dependency-upgrade-execution`** — risk-ordered upgrade batches with restore/build/test verification, then commit hand-off.

For single-phase needs, invoke those skills directly. Use this coordinator when you want the full audit → approval → upgrade flow in one place.

---

# When to use this skill

Use this skill whenever:

- The user asks to "update dependencies", "check for vulnerabilities", or "audit packages".
- Starting a new sprint or maintenance cycle — periodic dependency hygiene.
- A security advisory is reported and you need to assess impact, then potentially act.
- Before a major release — ensure dependencies are current and secure.

Do **not** use this skill for:

- Adding new dependencies — just add them directly.
- Debugging dependency conflicts during development — investigate directly.
- Framework upgrades (e.g., .NET 8 → .NET 9) — those are architectural changes requiring the Full tier workflow.
- A pure report (no intent to upgrade) — invoke `dependency-audit-report` directly.

---

# Workflow

Run the two atomic skills in strict order with an approval gate between them.

## Step 1: Audit (delegate to `dependency-audit-report`)

Run the `dependency-audit-report` skill. It performs manifest discovery, categorizes each
outdated/vulnerable package by risk, and presents the prioritized plan. It is **read-only** —
it never edits manifests or lock files.

At the end it asks how to proceed:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

**Approval gate:** do not advance to Step 2 until the user explicitly chooses an upgrade option.
If they choose option 4 (report only), stop here.

## Step 2: Upgrade (delegate to `dependency-upgrade-execution`)

Only after explicit approval, run the `dependency-upgrade-execution` skill with the approved
scope. It upgrades in risk-ordered batches (patch → minor → major), restores/builds/tests after
each batch, and on completion hands the verified changes to `git-commit-review`. This coordinator
does **not** define commits itself.

---

# Coordination

- **`dependency-audit-report`** — the read-only audit and prioritized plan (Step 1).
- **`dependency-upgrade-execution`** — the approved, verified upgrade batches and commit hand-off (Step 2).
- **Consult `security-engineer`** — for CVE impact assessment and exposure analysis.
- **Consult `backend-developer`** — for .NET-specific migration patterns when major packages change.
- **Consult `frontend-developer`** — for Angular/npm ecosystem upgrade patterns.
- **Consult `devops-engineer`** — if dependency updates affect Docker images or CI pipelines.
- **Delegate commits** to `git-commit-review` after upgrades are verified.

---

# Constraints

- **Audit before action** — always run `dependency-audit-report` (read-only) before any upgrade.
- **Approval gate is mandatory** — never start the upgrade step without explicit user approval.
- **Keep the steps atomic** — do not blend audit and upgrade logic here; delegate to the two skills.
- **Don't mix dependency upgrades with feature work** — keep dependency changes separate.
- **Delegate commits** — hand verified upgrades to `git-commit-review`; this skill does not own commit strategy.

---

## Final Rules (Anchor)

1. Always audit (read-only) before upgrading — never skip the `dependency-audit-report` step.
2. The approval gate between audit and upgrade is mandatory — never upgrade without explicit approval.
3. Delegate the detailed work to the two atomic skills and commits to `git-commit-review`; keep this coordinator thin.
> If anything above conflicts with these, **these win**.
