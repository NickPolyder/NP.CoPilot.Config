# Coordination

## Authority

Project contracts own mission, tooling, ownership, evidence, approvals and
delivery controls. Global guidance supplies defaults; local preferences cannot
waive project controls. Respect user restrictions and higher-priority runtime
instructions; resolve material conflicts explicitly.

Loaded guidance does not guarantee discovery precedence. Filenames/symlinks do
not prove active definitions, models or plugins. Preserve assigned model IDs and
approved overrides unless the user requests change.

## Work assignment

Do small/continuous work directly. Delegate substantial independent assignments
benefiting from separate context, or required reviews, not domain keywords.

| Role | Assignment |
|---|---|
| `investigator` | Read-only research, diagnosis, requirements and design analysis. |
| `implementer` | Approved code, tests, documentation or configuration changes. |
| `code-reviewer` | Independent read/search-only assessment of immutable inputs. |

The caller supplies relevant `skills/domain-guidance.md` sections from the
verified source. Domain focus is not another agent chain. Preserve separate
ownership for independently shippable work and required domain reviews;
test-only assignments never authorize production edits.

Agents are terminal: tools only, never skills or agents. Return additional needs
to the caller; do not bounce unresolved tasks or duplicate delegated research.

## Workflow ownership

Only one entry, coordinator or terminal workflow is active at a time:

- Entry workflows: `prd-workflow`, `feature-planning`.
- Thin coordinators: `dependency-audit`, `test-gap-analysis`.
- Terminal review workflows: `git-commit-review`, `full-code-review`.
- Other skills are bounded atomic tasks or documented phases.

Owners sequence only documented phases; atomic skills never invoke entry
workflows/coordinators. Standalone skills stop at the requested outcome, without
automatic next-phase prompts. Requested coordinators retain their gates; the
owner asks once, not again in each child.

A separate terminal workflow requires the owner and any parent to finish, or
explicit user-directed suspension for a checkpoint commit. Suspension records
pending work and resume conditions, releases active ownership, and never marks
blocked work complete. Resume after the terminal workflow ends, refreshing
affected evidence and approvals. Composition stays acyclic; `full-code-review`
remains explicit-user-only.
An explicit checkpoint request supplies suspension direction; do not ask twice.

## Handoffs

Provide outcome, scope, readable artifacts, revision, evidence, locked decisions
and stopping condition. Review intake requires immutable base/candidate context,
not a moving branch name.

Return changed artifacts, evidence/gaps and complete/blocked/paused/advisory
status. Keep recommendations separate.
