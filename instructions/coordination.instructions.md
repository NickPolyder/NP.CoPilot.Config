# Coordination

## Authority

Project contracts own repository mission, tooling, ownership, required evidence,
approvals and delivery controls. Global guidance supplies defaults; local
preferences may refine style but cannot waive those controls. Respect current
user restrictions and higher-priority runtime instructions. Resolve material
conflicts explicitly.

This is a policy for loaded guidance, not a guarantee of discovery precedence.
Do not infer an active definition, model, or plugin from a filename or symlink.
Preserve assigned model IDs and approved overrides unless the user requests a
change; choose task-appropriate models only within that authorization.

## Work assignment

Do small or continuous work directly. Delegate only a substantial independent
assignment that benefits from separate context, or a required review. Domain
keywords alone are not reasons to spawn agents.

| Role | Assignment |
|---|---|
| `investigator` | Read-only research, diagnosis, requirements and design analysis. |
| `implementer` | Approved code, tests, documentation or configuration changes. |
| `code-reviewer` | Independent read/search-only assessment of immutable inputs. |

Domain expertise is an assignment focus, not another agent chain. The caller
selects only relevant sections of `skills/domain-guidance.md` from the verified
configuration source and supplies them with the task. Keep separate ownership
for independently shippable work. A test-only assignment does not authorize
production edits. A required domain review remains required even though its
reviewer uses the same role card as the core reviewer.

Agents are terminal: use tools, never spawn agents or invoke skills. Return
additional-domain needs to the caller. Do not bounce the same unresolved task
between agents or duplicate a delegated investigation.

## Workflow ownership

Only one entry workflow or coordinator owns the work at a time:

- Entry workflows: `prd-workflow`, `feature-planning`.
- Thin coordinators: `dependency-audit`, `test-gap-analysis`.
- Terminal review workflows: `git-commit-review`, `full-code-review`.
- Other skills are bounded atomic tasks or documented phases.

An owner may sequence only its documented phases. Atomic skills never invoke
entry workflows or coordinators; composition must stay acyclic. A separate
terminal workflow starts only after the owning workflow finishes its state,
including its parent. Never mark blocked work complete to force a handoff.
`full-code-review` remains explicit-user-only.

## Handoffs

Provide the outcome, bounded scope, readable artifacts, covered revision,
existing evidence, locked decisions and stopping condition. Review intake must
identify immutable base/candidate context, not merely a moving branch name.

Return the result, changed artifacts, actual evidence or missing inputs, and
complete/blocked/advisory status. Keep additional recommendations separate.
