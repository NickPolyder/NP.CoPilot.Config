# {{REPO_NAME}} — Tasks

Phased breakdown of the work in [`PLAN.md`](PLAN.md). Phases are roughly
dependency-ordered; some can run in parallel (note it in the "Depends on"
column).

> **Tracking convention:** As phases complete, update the **Status** column
> here. This file is the human-readable source of truth for progress. Update it
> at session end so the next session sees current state.

| #  | Status   | Phase                                  | Depends on |
|----|----------|----------------------------------------|------------|
| 0  | pending  | {{PHASE_0 — e.g. spike / de-risk}}     | —          |
| 1  | pending  | {{PHASE_1}}                            | 0          |
| 2  | pending  | {{PHASE_2}}                            | 1          |
| 3  | pending  | {{PHASE_3}}                            | 2          |

> Status values: `pending` · `in progress` · `done ✅` · `blocked`.

## Decided up front

> Decisions locked during planning so they aren't re-litigated mid-flight. Link
> the ADR when one exists.

- {{DECISION_1}}
- {{DECISION_2}}

## Notes

- {{ANY_CROSS_CUTTING_NOTE — e.g. "Phases N–M are cross-system handoffs; see
  docs/handoffs/."}}
