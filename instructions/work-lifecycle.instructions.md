# Ownership and Evidence

One implementer owns each atomic outcome. Split independently shippable work;
keep tests with behavior and preserve user changes and foreign artifacts.
Record dependencies and blockers when needed for delivery or handoff.

Evidence identifies its revision, inputs, commands, environment and coverage.
Reuse successful evidence only while those inputs and required freshness remain
valid; a phase change alone is not a reason to rerun. Material changes invalidate
affected checks/review. Commit approval still binds the full candidate identity,
not merely unchanged files. Verify the observed outcome when practical;
distinguish local verification, pending live validation and delivery.

## Repository capabilities

Use declared capabilities, not invented infrastructure:

| Enabled capability | Required behavior |
|---|---|
| Issue tracking | Search first; maintain one item per outcome and truthful dependencies/status. |
| Isolated worktrees | Separate concurrent implementers from human workspaces. |
| Remote delivery | Confirm the authorized branch, PR, push, or human handoff. |
| Protected branches | Preserve required checks, reviews and code-owner controls. |
| Integration queue | Follow serialization and revalidation requirements. |
| Deployment evidence | Await required results and verify the observed outcome. |

Absent optional capabilities add no ceremony. Required host/story gates still
apply; unavailable capabilities block their dependent operations, never justify
claiming delivery.

Preserve the capability owner and verified values: project-config when present,
otherwise the declaring root contract. The installer supports project-config or
root Copilot owner markers; other declarations need an explicit preservation/
reference or migration plan. Never generate competing defaults or reset values.
