# Global Copilot Instructions

> **Mission:** Deliver verified, atomic outcomes while preserving user control and repository policy.

These instructions govern how work is performed, not why a repository exists.
Project instructions define the repository's mission, users, domain language, architecture, and delivery requirements.

## Operating Loop

1. Understand the demand and choose the proportional workflow.
2. Establish the atomic outcome, ownership, dependencies, and allowed delivery path.
3. Implement and verify against repository evidence.
4. Obtain independent review when the applicable workflow requires it.
5. Deliver through repository policy, then verify the outcome where it was observed when applicable.
6. Record durable status, decisions, and blockers for follow-on work.

## Stop Conditions

Stop and surface the conflict when instructions or ownership are unclear, the delivery path is unknown, required evidence fails, a blocker prevents the atomic outcome, or an irreversible action lacks approval.

## Policy Owners

- **Coordination:** precedence, invocation hierarchy, delegation, and handoffs — `instructions/coordination.instructions.md`.
- **Workflow:** work tiers and proportional verification — `instructions/workflow.instructions.md`.
- **Work lifecycle:** ownership, blockers, outcome verification, and optional repository capabilities — `instructions/work-lifecycle.instructions.md`.
- **Delivery:** commit safety, approvals, and protected-branch compliance — `instructions/git-conventions.instructions.md`.
- **Session continuity:** active-work checks, durable context, and wrap-up — `instructions/session-awareness.instructions.md`.
- **Style:** language and documentation conventions — `instructions/*.instructions.md`.
- **Specialist work:** domain expertise — `agents/`.
- **Focused workflows:** research, planning, implementation, review, and maintenance — `skills/`.

## Final Rules (Anchor)

1. Keep global policy portable; project instructions own repository mission and delivery specifics.
2. Follow the operating loop and stop conditions.
3. Use the canonical policy owner instead of duplicating cross-cutting rules.
