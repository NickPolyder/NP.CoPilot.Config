---
name: dependency-audit
description: >
  Audits project dependencies for outdated versions, known vulnerabilities,
  and license risks. Proposes a safe, incremental upgrade path with test
  verification at each step.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

This skill is a **thin coordinator**. It owns the end-to-end dependency-hygiene flow and the gate between audit and upgrade, but delegates the detailed procedures to two atomic skills:

- **`dependency-audit-report`** — read-only direct/transitive inventory,
  vulnerability/risk assessment, version-specific license evidence and declared
  policy comparison, plus a prioritized upgrade plan.
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
- Framework upgrades (e.g., .NET 8 → .NET 9) — those require explicit architectural scope and approval.
- A pure report (no intent to upgrade) — invoke `dependency-audit-report` directly.

---

# Workflow

Run the two atomic skills in strict order with an approval gate between them.

## Step 1: Audit (delegate to `dependency-audit-report`)

Run the `dependency-audit-report` skill. It discovers the full dependency graph,
categorizes version/vulnerability risks, and reports licenses against declared
policy, including current packages, transitives, conflicts, unknowns, and
not-assessed scopes. Its prioritized plan does not imply that an upgrade resolves
every license finding. It is **read-only** and never edits manifests or lock files.

At the end it asks how to proceed:

> **Audit complete. How would you like to proceed?**
> 1. Upgrade all (incremental, safest-first)
> 2. Critical + High only
> 3. Let me pick which ones
> 4. Just the report — I'll handle upgrades manually

**Approval gate:** do not advance to Step 2 until the user explicitly chooses an upgrade option.
If they choose option 4 (report only), stop here. Approval covers the selected
changes, not automatic acceptance of unresolved license obligations or policy conflicts.

## Step 2: Upgrade (delegate to `dependency-upgrade-execution`)

Only after explicit approval, run the `dependency-upgrade-execution` skill with the approved
scope and license-policy constraints. It upgrades in risk-ordered batches
(patch → minor → major), restores/builds/tests after each batch, and returns its
evidence to this coordinator. Complete this coordinator's state before offering
a separate `git-commit-review` handoff; neither phase completion nor upgrade
approval starts a terminal workflow inside this coordinator.

---

# Coordination

- **`dependency-audit-report`** — the read-only audit and prioritized plan (Step 1).
- **`dependency-upgrade-execution`** — the approved, verified upgrade batches and commit hand-off (Step 2).
- The audit phase may use `investigator` for substantial unresolved exposure,
  license or migration questions. The approved execution phase may use
  `implementer` for bounded package, lockfile, container or pipeline changes.
- **Recommend commit handoff** to `git-commit-review` only after this coordinator
  is complete and upgrades are verified; preserve its independent approval gates.

---

# Constraints

- **Audit before action** — always run `dependency-audit-report` (read-only) before any upgrade.
- **Approval gate is mandatory** — never start the upgrade step without explicit user approval.
- **Keep the steps atomic** — do not blend audit and upgrade logic here; delegate to the two skills.
- **Don't mix dependency upgrades with feature work** — keep dependency changes separate.
- **Separate delivery** — return verification and unresolved license decisions;
  after this coordinator completes, recommend `git-commit-review`, never nest it.

---
