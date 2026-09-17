# Ownership and Evidence

One implementer owns each atomic outcome. Split independently shippable work;
keep tests with the behavior they cover. Preserve user changes and foreign
artifacts. Record dependencies and blockers when they affect delivery or a
handoff, not as ceremony for every small task.

Validation, review and delivery evidence must identify the revision covered.
Material changes invalidate affected evidence: repeat the relevant checks and
review on the new candidate. Use the repository's actual delivery path, never an
assumed direct push. Verify the originally observed outcome when practical;
distinguish local evidence from unavailable integration or deployment evidence.

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

Absent optional capabilities add no ceremony; actual host protections and
required story gates still apply. An unavailable required capability is a
blocker, not permission to claim delivery.

Preserve the existing capability owner and verified values. Project-config
declarations are canonical when present; otherwise preserve the declaring root
contract. The installer supports project-config or root Copilot owner markers.
Other root declarations require an explicit preservation/reference or migration
plan. Never generate competing default-disabled tables or silently reset values.
