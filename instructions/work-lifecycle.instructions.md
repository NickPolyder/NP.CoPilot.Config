# Work Lifecycle

> **Intent (anchor):** Define a portable lifecycle for verified, atomic outcomes without requiring a particular issue tracker, worktree system, branch model, or deployment platform.
> **Always:** make the outcome, owner, dependencies, candidate revision, and required evidence explicit when the work tier or project capabilities require them.
> **Never:** invent repository capabilities, conceal blockers, claim completion without required evidence, or bypass a configured delivery path.

## Lifecycle

1. **Ready** — the atomic outcome, owner, dependencies, and delivery path are understood.
2. **Active** — one implementing agent owns the atomic outcome.
3. **Blocked** — evidence and the dependency are recorded; release an active claim when the configured tracker supports claims.
4. **Under review** — validation and independent review reference the exact candidate revision.
5. **Delivered** — the configured delivery evidence is complete and the observed outcome is verified when applicable.

Use the smallest lifecycle evidence that matches the work tier.
Trivial work normally needs only the applicable local verification.
Standard and Full work must retain enough evidence for the next agent or reviewer to understand the outcome and its status.

## Atomic Outcomes and Blockers

- Split work when outcomes, owners, repositories, or independently shippable changes differ.
- Keep tests with the behavior they verify.
- When a separate blocker prevents the current outcome, preserve the evidence, record or link the dependency in the configured system, and return the current work to a truthful blocked or ready state.
- Do not silently expand the current outcome to resolve unrelated findings.
- Perform root-cause analysis for incidents, recurrences, regressions, or systemic failures when repository policy requires it; do not require it for every isolated defect.

## Exact-Revision Evidence

Validation, review, CI, and delivery evidence must identify the candidate revision they cover.
After a material change, repeat affected validation and review for the new revision.
Use the project delivery path—staged snapshot, commit SHA, pull-request head SHA, merge queue result, or deployment run—rather than assuming a direct push to `main`.

## Outcome Verification

For user-facing, incident-driven, integration, or deployment work, verify the original observed outcome when practical.
State clearly when local verification is the highest available evidence and identify any remaining external verification.

## Repository Delivery Capabilities

Project configuration may enable the following capabilities.
Disabled or absent capabilities impose no additional ceremony.

| Capability | When enabled |
|---|---|
| Issue tracking | Search before creating work; use one tracked item per atomic outcome; record dependencies and truthful state. |
| Isolated worktrees | Concurrent implementers work outside human workspaces in separate worktrees. |
| Remote delivery | Confirm the allowed branch, pull request, push, or human-handoff path before remote mutation. |
| Protected branches | Follow required reviews, checks, code-owner, and branch rules; never bypass them. |
| Integration queue | Follow the configured serialization and revalidation rules. |
| Deployment evidence | Await required CI/deployment evidence and verify the observed outcome when applicable. |

## Final Rules (Anchor)

1. Work one atomic outcome at a time and keep blockers truthful.
2. Bind required validation and review evidence to the exact candidate revision.
3. Use only repository capabilities declared by project configuration.
4. Follow the configured delivery path; do not assume direct write access to `main`.
