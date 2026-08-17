# Instruction Architecture Comparison and Simplification Proposal

**Date:** 2026-08-17
**Status:** Implemented on 2026-08-17.

## Decision Summary

Keep the current layered configuration, user approval, bounded delegation, and index-only commit-review safeguards.
Simplify the system by assigning each cross-cutting rule a single canonical owner, making the root instruction a compact operating contract, and removing copied coordination boilerplate from every agent and skill.

Adopt the friend's strongest delivery principles only when repository capabilities support them:

- one atomic outcome at a time;
- independently reviewed, exact-revision changes;
- revalidation after material changes;
- verification at the original observation point;
- explicit handling of blockers and dependencies.

Do not adopt mandatory issue creation, Cortex terminology, universal RCA, direct pushes to `main`, or a global single-integration-writer rule.

## Implementation Status

The root operating contract, work-lifecycle policy, delivery policy, project capability templates, bootstrap template, bootstrap skill, README, and coordination reference now implement this proposal.
Agent and skill definitions are consolidated separately to remove repeated global-policy text while preserving their domain- and workflow-specific guidance.

## Scope and Evidence

This comparison evaluates the supplied excerpt only, not the friend's complete configuration.
It compares that excerpt with the active configuration repository:

| Area | Current evidence |
|---|---|
| Root contract | `copilot-instructions.md` is a short routing index. |
| Global policy | `instructions/` has 13 scoped files covering workflow, coordination, Git, session behavior, style, and communication. |
| Specialist behavior | `agents/` has 17 domain agents; their combined definitions are approximately 3,787 lines. |
| Workflows | `skills/` has 25 skills; their combined definitions are approximately 3,825 lines. |
| Commit integrity | `skills/git-commit-review/SKILL.md` materializes, validates, and reviews an index-only snapshot. |
| Planning and execution | `feature-planning`, `task-breakdown`, and `implementation-runner` use approved, dependency-aware work. |
| Repository onboarding | `repo-bootstrap` and `templates/repo-bootstrap/` create a project-local operating manual and durable plan/task records. |

The size is not independently a defect.
The relevant signal is that global rules are repeated in many definitions: precedence, orchestration prohibitions, delegation limits, approval gates, and final-rule anchors.
Repeated policy creates drift risk and forces users and agents to reconstruct the real operating contract from many files.

## Comparison Model

The two systems are assessed against the following criteria:

| Criterion | Meaning |
|---|---|
| Clarity | An agent can identify the next action and stopping conditions. |
| Safety | The process prevents unsafe, unreviewed, or irreversible changes. |
| Review integrity | Review applies to the exact revision that ships and is independent of the author. |
| Portability | The rule works across repositories, providers, permissions, and team sizes. |
| Enforceability | Required controls can be checked by tools or repository configuration. |
| Flow efficiency | The process avoids unnecessary ceremony and limits work in progress. |
| Traceability | Work, decisions, evidence, and follow-up are discoverable. |
| Context cost | The system avoids repeating the same rules in every active prompt. |

## What the Friend's Excerpt Does Well

| Principle | Why it is strong | Current coverage | Gap to address |
|---|---|---|---|
| Starts from a mission | Links process to quality and cycle time rather than listing isolated rules. | The root has an intent, but no delivery mission. | Add a one-sentence mission to the root contract. |
| Uses a visible end-to-end loop | Intake, ownership, execution, review, integration, and verification are sequenced in one place. | Our workflow is distributed among `workflow`, `git-conventions`, skills, and templates. | Add a compact operating loop with links to canonical owners. |
| Splits work by independently shippable outcome | Avoids mixed commits, unclear ownership, and accidental coupling. | Strong in `git-commit-review`; partial in task breakdown. | Make atomic outcome the shared vocabulary for planning, implementation, and commit review. |
| Requires exact-revision independent review | Prevents approving a different revision from the one delivered. | Strongest current equivalent is the index-only snapshot review. | State the exact-revision guarantee explicitly and extend it to pull-request or protected-branch workflows. |
| Repeats affected verification after material change | Prevents stale review evidence after a fix. | `git-commit-review` has scoped re-review. | Make the general rule canonical rather than workflow-local. |
| Verifies the original demand | Tests the user-observed outcome, not only an internal proxy. | Present in code review functional-completeness guidance but not global process. | Add an outcome-verification rule for user-visible or incident-driven work. |
| Handles blockers explicitly | Preserves evidence, links dependent work, and returns work to a ready state. | Dependencies exist in task planning; durable handoff exists in bootstrap. | Define a portable blocked-work protocol. |
| Limits concurrent integration | Recognizes that integration is a serial, high-conflict operation. | No global policy. | Add repository-capability guidance, not a universal rule. |

## Where the Friend's Excerpt Is Weak or Risky

| Concern | Why it is a problem | Recommendation |
|---|---|---|
| Undefined operating vocabulary | `Cortex`, `flash`, module ownership, request groups, and configuration closure are opaque without platform-specific definitions. | Reject as global language; project integrations may define equivalent terms locally. |
| Mandatory issue workflow | Creating, searching, claiming, and closing issues for every code change penalizes trivial and exploratory work. | Adapt as an optional repository workflow for tracked, multi-session, or multi-agent work. |
| Direct push to `main` | Bypasses protected branches, pull requests, mandatory CI, code owners, and release controls. | Reject; defer delivery method to repository branch protection and project instructions. |
| Push authority as a precondition | Important for autonomous agents, but it should not prevent useful local preparation or a PR handoff. | Adapt: check the allowed delivery path before a remote-changing action; do not treat missing direct-push authority as a failure. |
| Universal RCA | Root-cause analysis is valuable for significant defects but expensive and unhelpful for every isolated defect. | Adapt with risk thresholds: incidents, recurrences, regressions, and systemic failures require RCA. |
| “Fail or Inconclusive never ships” | Correct intent, but “inconclusive” needs a defined evidence threshold and an escalation path. | Adapt: unresolved required checks block delivery unless the user explicitly accepts a documented exception allowed by repository policy. |
| One integration writer per repository | Useful in high-concurrency autonomous systems; overly restrictive for normal protected-branch workflows. | Adapt only for automation-managed shared branches or deployment trains. |
| Drive inventory to zero | Can incentivize hiding or closing work prematurely despite the stated caveat. | Reject as a global target; prioritize accurate status and agreed service levels. |
| Prescriptive tool and process coupling | The workflow assumes issue bindings, authority data, isolated worktree infrastructure, and deployment observability. | Keep these as capability-gated repository extensions. |

## Where Our Current System Is Stronger

| Strength | Evidence | Preserve |
|---|---|---|
| Configuration precedence | Root and coordination instructions define global → project → local precedence. | Yes; make `coordination.instructions.md` its sole canonical owner. |
| Proportionate process | `workflow.instructions.md` distinguishes Trivial, Standard, and Full work. | Yes; use this tiering to gate issue, worktree, and RCA requirements. |
| Direct-action bias | Coordination discourages reflexive delegation and needless process. | Yes; retain as a root-level operating principle. |
| Bounded delegation | Coordination establishes hierarchy and a hard handoff depth cap. | Yes; retain, but reference it from agents instead of copying it. |
| Explicit user control | Git conventions require verification and approval before non-trivial commits. | Yes; preserve and make it the default exception authority. |
| Index-only review integrity | Commit review validates and reviews a materialized staged snapshot. | Yes; retain unchanged as the primary local commit workflow. |
| Risk-based specialist review | Commit review selects specialists from actual staged-change signals. | Yes; retain rather than require indiscriminate review fan-out. |
| Safe review scope | Full review is explicit-only; normal commit review is time-bounded. | Yes; retain the distinction. |
| Reusable domain expertise | Specialists and skills separate planning, execution, review, security, testing, and documentation. | Yes; preserve domain ownership while removing global process duplication. |

## Where Our Current System Needs Improvement

| Concern | Impact | Target change |
|---|---|---|
| No compact delivery mission or operating loop | The root explains file locations but not how a change moves safely from demand to verified outcome. | Rewrite the root around mission, loop, stop conditions, and routing. |
| Policy is duplicated | Changes require many synchronized edits and may drift. | Give every cross-cutting rule one canonical owner. |
| Agent prompts carry global coordination prose | Domain context is diluted by repeated rules in 17 files. | Remove copied precedence, anti-loop, and generic handoff text; retain a short reference to canonical policy. |
| Skill prompts repeat shared constraints | Atomic-skill and approval language appears many times. | Keep only workflow-specific entry, outputs, and exceptions in each skill. |
| Intake and blocked-work lifecycle is underdefined | Multi-session and multi-agent work may lack clear ownership, dependencies, and release behavior. | Add a portable work-state policy with optional issue integration. |
| Delivery-path authority is implicit | Agents may assume direct push or treat lack of push permission as a blocker too early. | Add a delivery-path check before remote changes and define fallback to PR or human handoff. |
| Exact-revision guarantee is local to staged commits | The strong snapshot model is not expressed for branch/PR workflows. | Define a general review-evidence rule; project policy selects snapshot, commit SHA, PR head SHA, or CI run. |
| Outcome verification is not a shared policy | Process can stop at local tests even when the original observation point differs. | Add a tiered outcome-verification rule. |

## Adopt, Adapt, and Reject

| Excerpt principle | Decision | How it applies here |
|---|---|---|
| Atomic, independently shippable outcomes | **Adopt** | Use in planning, implementation, review, and commit language. |
| Independent review on the delivered revision | **Adopt** | Preserve index-only review and require evidence bound to the delivery revision. |
| Revalidate and re-review after material changes | **Adopt** | Promote from commit-review detail to general verification policy. |
| Verify at the original observation point | **Adopt** | Require for user-facing, incident, integration, and deployment work when practical. |
| Explicit blocker evidence and dependency tracking | **Adapt** | Use tasks, issues, or durable handoff records according to project capability. |
| One active item per implementing agent | **Adapt** | Apply to Full-tier or tracked autonomous work; do not constrain normal interactive micro-tasks. |
| Isolated worktrees | **Adapt** | Require only where project configuration enables multi-agent concurrent editing or human-workspace protection. |
| Check authority before implementation | **Adapt** | Check before remote mutation; permit local work and PR/human handoff when direct write is unavailable. |
| Issue search, claim, and close loop | **Adapt** | Enable for repositories configured with issue-backed work, not globally. |
| RCA for every defect | **Adapt** | Require based on impact, recurrence, or systemic risk. |
| Single integration writer | **Adapt** | Enable only for automation-managed shared branches or integration queues. |
| Cortex module and configuration closure | **Reject** | Not portable and undefined in this environment. |
| Direct push to `main` | **Reject** | Follow branch protection and repository delivery policy. |
| Zero open inventory target | **Reject** | Prefer truthful work state, priority, and service-level objectives. |

## Target Architecture

### Root Operating Contract

Keep `copilot-instructions.md` below roughly one screen of content.
It should contain only:

1. **Mission:** deliver verified, atomic outcomes while preserving user control and repository policy.
2. **Operating loop:** understand demand → choose proportional workflow → establish ownership and delivery path → implement and verify → independently review when required → deliver through repository policy → verify the observed outcome → record status.
3. **Stop conditions:** conflicting instructions, unclear owner or delivery path, failing required evidence, unresolved blocker, or destructive action without approval.
4. **Routing index:** links to the sole owner for coordination, workflow, Git delivery, session state, language style, agents, and skills.

The root must not repeat detailed precedence, delegation caps, commit mechanics, tool-specific commands, or specialist tables.

### Canonical Policy Ownership

| Concern | Canonical owner | Consumers reference it; do not restate it |
|---|---|---|
| Precedence and invocation hierarchy | `instructions/coordination.instructions.md` | Root, templates, agents, and skills. |
| Delegation and handoff protocol | `instructions/coordination.instructions.md` | Root, agents, skills, `docs/agent-coordination.md`. |
| Work tiers and verification proportionality | `instructions/workflow.instructions.md` | Root, planning/execution skills. |
| Work lifecycle, blockers, outcome verification | New `instructions/work-lifecycle.instructions.md` | Root, task/planning/execution skills, bootstrap template. |
| Commit and delivery-path safety | `instructions/git-conventions.instructions.md` | Root, commit-review skill, bootstrap template. |
| Exact-revision review workflow | `skills/git-commit-review/SKILL.md` | Git policy and other skills link only. |
| Session continuation and durable handoff | `instructions/session-awareness.instructions.md` | Root, bootstrap template, resume workflow. |
| Project capability declarations | `templates/project-config*.instructions.md` and generated `.github/instructions/project-config.instructions.md` | All workflow policy reads capabilities from this file. |
| Domain-specific implementation expertise | `agents/*.md` | Coordination policy, not individual agents, owns cross-agent rules. |

### New Capability-Gated Work Lifecycle

Add `instructions/work-lifecycle.instructions.md`.
It must not introduce a compulsory issue tracker.
It defines a policy that activates controls from project configuration:

| Capability | When enabled | Required behavior |
|---|---|---|
| `issueTracking` | The project provides an issue system and marks work as tracked. | Search before creating; use one issue per atomic outcome; preserve blockers and dependencies. |
| `isolatedWorktrees` | The project supports concurrent agents or protects human workspaces. | Each concurrent implementer uses an isolated worktree. |
| `remoteDelivery` | A remote delivery path is configured. | Confirm branch, push, PR, or human-handoff authority before remote mutation. |
| `protectedBranches` | Mainline requires PR/CI/review. | Deliver through the protected path; never bypass it. |
| `integrationQueue` | The project has a merge queue or shared integration branch. | Use its serialization rules and revalidate the resulting revision. |
| `deploymentEvidence` | A deployed environment and observability are configured. | Await required CI/deployment evidence and verify the original observed outcome. |

The lifecycle has five portable states:

1. **Ready:** outcome, owner, dependencies, and delivery path are known.
2. **Active:** one agent is implementing the atomic outcome.
3. **Blocked:** evidence and dependency are recorded; the active claim is released when the repository supports claims.
4. **Under review:** required validation and independent review reference the candidate revision.
5. **Delivered:** repository delivery evidence and outcome verification are recorded.

### Agents and Skills

Agent definitions should retain:

- role, domain boundaries, technical guidance, review/implementation checklists, and output expectations;
- a concise line such as “Follow global coordination and delivery policy; do not restate it.”

They should remove:

- copied precedence paragraphs;
- copied anti-loop paragraphs;
- repeated generic escalation tables when a short domain boundary suffices;
- duplicated final anchors for global process rules.

Skills should retain:

- purpose, exact trigger, inputs, output path, workflow-specific phases, and explicit non-goals;
- only exceptions that differ from canonical policy.

Skills should replace repeated global wording with direct references:

- `codebase-research`, `feature-design-doc`, `task-breakdown`, and `implementation-runner` reference the work lifecycle for ownership, dependencies, and blocked work;
- `git-commit-review` remains the canonical exact-revision review implementation;
- `repo-bootstrap` generates the project capability declarations and lifecycle references instead of another broad operating manual.

### Project and Bootstrap Configuration

Extend project-config templates with an optional `## Agent Delivery Capabilities` section:

```markdown
| Capability | Enabled | Repository-specific rule |
|---|---:|---|
| Issue tracking | No | |
| Isolated worktrees | No | |
| Remote delivery | Yes | Pull request only |
| Protected branches | Yes | Required checks: ... |
| Integration queue | No | |
| Deployment evidence | No | |
```

The generated repo-level operating manual should state repository-specific facts and capability values only.
It should link to global policy instead of reproducing global workflow, commit, and handoff rules.

## File-by-File Change Map

| Path | Action | Intended change |
|---|---|---|
| `copilot-instructions.md` | Rewrite | Replace the long quick-reference policy summary with mission, loop, stop conditions, and a compact routing index. |
| `instructions/coordination.instructions.md` | Consolidate | Remain the sole owner of precedence, hierarchy, delegation, and handoffs; remove workflow and test details owned elsewhere. |
| `instructions/workflow.instructions.md` | Refine | Keep tier classification and proportional verification; link lifecycle and delivery policy rather than restating them. |
| `instructions/work-lifecycle.instructions.md` | Add | Define portable work states, blockers, outcome verification, and capability-gated issue/worktree/integration behavior. |
| `instructions/git-conventions.instructions.md` | Refine | Own delivery-path authority, protected-branch compliance, user approvals, and commit safety; link exact-revision mechanics to the skill. |
| `instructions/session-awareness.instructions.md` | Refine | Own only continuation, durable context, and wrap-up; link lifecycle state rather than duplicating it. |
| `agents/*.md` | Consolidate | Remove copied global coordination and precedence content; retain domain-specific guardrails and boundaries. |
| `skills/*/SKILL.md` | Consolidate selectively | Replace copied global policies with links; preserve each skill's unique workflow and output contract. |
| `skills/git-commit-review/SKILL.md` | Retain and clarify | Keep snapshot validation and re-review mechanics; clarify delivery evidence may be PR/CI governed rather than direct main push. |
| `skills/repo-bootstrap/SKILL.md` | Rewrite targeted sections | Generate a short project contract and capability declarations, not a broad duplicate of global policy. |
| `templates/repo-bootstrap/copilot-instructions.template.md` | Rewrite | Reduce to repo facts, hard rules, verified commands, delivery capabilities, and local exceptions. |
| `templates/project-config*.instructions.md` | Extend | Add delivery capability declarations and repository-specific evidence commands. |
| `docs/agent-coordination.md` | Consolidate or remove | Keep only if it becomes a short explanatory companion; otherwise link directly to canonical coordination policy. |
| `README.md` | Update | Describe the simplified architecture and canonical policy ownership. |
| `docs/features/instruction-architecture-comparison.md` | Retain | Record this proposal and future accepted decisions. |

## Migration Sequence

1. **Establish canonical ownership**
   - Add the work-lifecycle policy.
   - Clarify the boundaries of coordination, workflow, Git, and session policies.
   - Update the root to route to those owners.

2. **Make project capabilities explicit**
   - Extend project-config templates.
   - Update repo-bootstrap templates and skill behavior.
   - Preserve empty or `No` defaults so existing repositories retain current behavior.

3. **Remove duplicated global process**
   - Update agent definitions in one consistent pass.
   - Update skills in groups: planning/execution, review, bootstrap/maintenance.
   - Preserve workflow-specific instructions and final rules that are not global duplicates.

4. **Reconcile documentation**
   - Update README and either retire or reduce `docs/agent-coordination.md`.
   - Add concise migration notes for users with existing local/project overrides.

5. **Validate and release**
   - Run structural checks and scenario walkthroughs.
   - Review resulting changes as one or more atomic candidates with `git-commit-review`.
   - Update symlink-install documentation only after the new paths and templates are final.

Do not delete legacy duplicated text until its canonical owner is present and every consumer links to it.

## Compatibility and Risk Controls

- Existing project configuration remains valid because every new capability defaults to disabled.
- Existing branch and PR policy takes precedence over global delivery guidance.
- A repository without issues, worktrees, deployments, or remote authority continues to use the current tiered workflow.
- Direct-to-main instructions are never generated; delivery follows project configuration and host protection.
- Agents must not infer that a capability is available merely because a tool exists.
- The migration should be broken into reviewable changes: canonical policy first, consumers second, documentation third.

## Validation Plan

### Structural Checks

- Each cross-cutting rule has exactly one canonical owner in the ownership table.
- `rg` finds no copied precedence or anti-loop boilerplate in agent definitions after consolidation.
- Every root-level operational statement links to an owner rather than redefines it.
- All template placeholders and generated examples provide valid disabled defaults for optional capabilities.
- README paths and installer behavior still match the resulting repository layout.

### Scenario Walkthroughs

| Scenario | Expected outcome |
|---|---|
| Trivial documentation correction | Tiered workflow remains lightweight; no issue, worktree, or specialist review is required. |
| Standard code fix | Atomic outcome, tests, and normal review/commit approval are required; issue tracking is used only if project-enabled. |
| High-risk security or migration change | Risk-based specialist review and exact-revision evidence are required; protected-branch policy determines delivery. |
| Concurrent multi-agent project | Enabled worktrees isolate implementers; each has one active atomic outcome; integration queue rules serialize only when configured. |
| External blocker | Evidence and dependency are recorded; the current item becomes blocked and is not falsely completed. |
| Fix after review | Affected validation and review evidence are refreshed for the changed revision. |
| Deployment or incident fix | CI/deployment evidence and original-observation verification are captured when configured. |
| No remote write authority | Local validation can proceed; remote delivery routes through pull request or explicit human handoff. |

### Acceptance Criteria

- The root contract communicates mission, loop, and stop conditions in one short read.
- No global workflow rule is intentionally duplicated across root, agents, skills, templates, and docs.
- Global rules remain portable when issues, worktrees, PRs, CI, deployment, or external orchestration systems are absent.
- When those capabilities are present, the configuration requires traceable ownership, dependency handling, exact-revision review evidence, and appropriate delivery verification.
- Current safeguards for user approval, protected branches, secrets, staged snapshots, and risk-based review are preserved or strengthened.
- The final architecture makes it easier to determine where a policy belongs and to change it without drift.
