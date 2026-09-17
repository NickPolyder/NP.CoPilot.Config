# Copilot Configuration Hardening

**Status:** Approved definition corrections implemented in repository text.
Earlier local verification is recorded below; active-session/installation
adoption and external-provider regeneration remain unverified.

This is the hardening record, not the current instruction-size baseline.
The later approved [lean revision](../../README.md#lean-operating-model) removes
duplicate anchors and replaces domain-agent textbooks with three role cards and
on-demand notes. The executable safety fixes and required review/approval gates
remain; historical verification counts below do not validate the lean revision.

## Purpose

Harden the global Copilot configuration without replacing its existing operating model.
The work addresses the configuration review completed on 2026-08-25: capability enforcement, installer recovery, MCP architecture, policy precision, structural validation, and documentation drift.

## Locked Decisions

| Area | Decision |
|---|---|
| Scope | Address all review findings in dependency-ordered phases. |
| Playwright | Run local `@playwright/mcp@latest` under the existing user-approved mutable-version waiver; the remote Playwright service and port remain removed. |
| Hooks | Defer native hooks until the core controls have proved stable. |
| AgentMemory | Keep the plugin as the implementation/generator owner; a narrow correction to the visible ignored local instruction copy does not change or vendor that external source. |
| Review reports | Review workflows persist reports; `code-reviewer` returns findings only. |
| Skill metadata | Remove inert frontmatter metadata; do not replace it with permissive `allowed-tools`. |
| Context (original, superseded) | The original plan retained edge anchors. The authorized lean revision removes duplicated anchors while retaining substantive constraints once. |

## Protected Invariants

- The global configuration remains a layered, proportional workflow with explicit user approval gates.
- `git-commit-review` continues to materialize and validate an index-only snapshot before reviewers run.
- Plugin-managed AgentMemory artifacts are not duplicated or removed by this repository.
- Tests use isolated temporary targets and never mutate the active `~/.copilot` installation.
- Installer operations either complete or restore the state that existed before the operation.
- User-owned MCP entries remain preserved and are never printed in status output.
- The repository does not add broad command-deny hooks, HTTP hooks that inspect code, or a metadata-generation pipeline.

## Phases

| Phase | Outcome | Status |
|---|---|---|
| 1 | Structural validator and isolated regression fixtures | Complete |
| 2 | Transactional, recoverable global and project installers | Complete |
| 3 | Enforceable read-only review capability and bounded review cycles | Complete |
| 4 | Pinned local Playwright and remote-stack convergence | Complete |
| 5 | Explicit skill composition, precedence, and routing policy | Complete |
| 6 | Metadata cleanup, accurate documentation, validation integration, and context measurement | Complete |

## Validation Contract

The repository has a dependency-free PowerShell 7 structural validation entry point:

```powershell
pwsh -NoProfile -File .\scripts\Validate-Config.ps1
```

It checks selected configuration structure, references, inventory entries, policy wording, version pinning, and MCP syntax.
The orchestration map and wording assertions do not prove general semantic consistency or runtime behavior.
Read-only configuration/Compose checks must not require a private `.env` or a
real SearXNG secret. Use an explicitly synthetic, validation-only value scoped
to the check process, or a no-interpolation syntax-check path, and report only
the structure/syntax actually checked. Never persist or reuse the synthetic
value for deployment. Actual deployment independently rejects missing or
placeholder keys and must not disclose real secret values.
Installer behavior is validated separately against isolated temporary targets.
Applying installer changes to the active user configuration remains a user-approved manual step after repository checks pass.

## Completed Work

The phase descriptions and counts below record earlier hardening runs, not new
verification of the active installation.
The September follow-up corrects gaps found after those phases.

### Phase 1: Structural Validation

- Added `scripts\Validate-Config.ps1` with PowerShell 7 syntax enforcement, frontmatter validation, identity and model checks, routing-reference checks, orchestration checks, README inventory checks, MCP JSON/version checks, optional Compose validation, and critical review-policy invariants.
- Added `tests\ValidateConfig\` with a dependency-free, out-of-process fixture suite that creates and removes GUID-scoped temporary roots only.
- The suite covers valid configuration, frontmatter failures, invalid routing references, absent orchestration nodes, inventory drift, malformed and empty JSON, mutable-version case handling, Compose validation, missing review invariants, and empty definition collections.
- `pwsh -NoProfile -File .\tests\ValidateConfig\Run-ValidateConfigTests.ps1` passes all 54 tests, including the narrow Playwright `@latest` waiver.
- The validator completes against the repository with all 52 checks passing.

### Phases 2–6: Operational and Policy Hardening

- Reworked `install.ps1` into a PowerShell 7 transactional installer with
  preflight validation, `-WhatIf`, timestamped backups, manifests, recovery,
  redacted status, repair, safe uninstall, and MCP three-way ownership merge.
  Its isolated regression suite passes all 15 tests, including repeated
  revision/uninstall and foreign-symlink restoration cases identified through
  independent review.
- Reworked `install-project.ps1` for PowerShell 7 with non-interactive
  conflict handling, recoverable `-Force`, transactional manifests/backups,
  hash-based idempotence, safe uninstall, and reversible managed `.gitignore`
  changes. Its isolated PowerShell 7 suite passes all 17 tests, including
  `-WhatIf`, forced restoration, conflict retention, Git repository preflight,
  legacy uninstall, managed `.gitignore`, and deterministic transaction rollback.
  Targeted independent review confirmed its template-refresh restore-point and
  fresh-copy rollback fixes.
- Restricted `code-reviewer` to `read` and `search`; the review workflows now
  own persisted reports, and exhaustive review has a two-cycle default cap.
- Removed the remote Playwright container and browser-control port, pinned the
  SearXNG deployment image, and retained local `@playwright/mcp@latest` under
  the user's explicit mutable-version waiver.
- Defined bounded skill composition, conflict-resolution wording, deterministic
  resume state mapping, explicit test-strategy approval, and specialist routing
  boundaries for full-stack ownership, observability, and testing.
- Removed inert agent and skill frontmatter metadata, reconciled the README
  inventory, documented the validator, and added an index-only Git pre-commit
  hook for configuration changes.
- Measured the always-loaded root/instruction context at 53,338 characters
  (approximately 13,340 tokens). No additional safe trimming was identified:
  the remaining material is scoped instruction, non-duplicated guidance, or
  load-bearing intent/final-rule anchors.

## Follow-up Corrections (2026-09-15)

### Installer Ownership and Publication

Project uninstall now requires a `Managed` artifact before considering its hash
for deletion or restoration.
A previously preserved conflict remains unowned through repeated installation,
including when a later template happens to match its bytes.
Explicit `-Force` adoption remains available.
Matching user MCP entries without prior ownership records are also preserved,
not silently claimed by the global installer.

Both installers publish manifests inside the install/repair rollback boundary.
They write a temporary sibling file and replace the manifest through
`System.IO.File.Move` with overwrite, rather than a provider-level
`Move-Item -Force`.
Failed publication rolls back managed artifact changes while preserving prior
manifest bytes; only unpublished temporary files are eligible for cleanup.

This is install/repair failure handling, not a new all-or-nothing uninstall
transaction or a power-loss recovery guarantee.
No active user installation was adopted or repaired as part of this follow-up.

### Review and Policy Corrections

The [commit-review procedure](git-commit-review-redesign.md) now distinguishes
the complete index tree from changed paths and refreshes candidate identity
after fixes.
The [coordination reference](../agent-coordination.md) records terminal
delegation, proportional test/documentation work, and outcome-based specialist
guidance.
The user's trivial auto-commit preference is unchanged.

New hooks, expanded hook triggers, runtime inventory tooling, and a behavioral
evaluation framework remain deferred.

### Local Verification

The September corrections were exercised against disposable targets and
repositories, with no live installation or remote delivery.

| Check | Result |
|---|---|
| Global installer regression suite | 18 passed |
| Project installer regression suite | 24 passed |
| Commit-review wording regression suite | 7 passed |
| Git snapshot procedure suite | 2 passed |
| Configuration regression suite | 54 passed |
| Configuration validator (`-SkipDockerCompose`) | 51 checks passed |
| Review-policy validator | 30 selected wording checks passed |

The installer cases cover preserved conflicts, repeat/template-match handling,
explicit adoption, matching unowned MCP entries, publication failures after
artifact changes, byte-exact prior manifests, and temporary-file cleanup.
The snapshot cases cover full-tree versus changed-path scope, deleted and
renamed files, unstaged isolation, and fresh trees after restaged fixes.
These results are local evidence, not a behavioral benchmark of agent execution.
Commands are listed in the [repository validation reference](../../README.md#validation).

### Lessons

Passing isolated cases is not proof that all lifecycle sequences are covered.
Ownership must survive repeated operations, and failure injection must reach
state publication after artifacts have changed.
Structural policy checks should state their limits rather than imply measured
agent compliance.

## Approved Definition Corrections (2026-09-16)

These corrections keep the existing roles, assigned model IDs, approval gates,
trivial auto-commit preference, Playwright waiver, and native-hook deferral.
The scope is instruction/agent/skill/prompt text and related documentation,
not proof of workflow execution:

| Requests | Corrected contract |
|---|---|
| CR-M14 | License inventory covers direct/transitive package versions, source evidence, declared policy/obligations, and separate conflict/unknown/not-assessed output even without an upgrade or CVE. |
| CR-M15 | Scaffolding selects verification commands and cwd for the discovered target component, with explicit absent-runner evidence. |
| CR-M16–M17 | Reviewer intake is immutable and missing-evidence-aware; active-workflow participation remains read/search-only. QA/Test Engineer return terminal evidence-bearing handoffs without production edits. |
| CR-M18–M20 | Completion is capability-aware; secret storage and approved runtime injection are distinct; pagination ordering/cursors agree; Service Fabric named updates retain state-loss guards; Blazor Auto preserves component-instance render mode. |
| CR-M21 | Existing project/cross-agent record maintenance coexists with plugin persistence; redundant unsolicited session exports remain prohibited. |
| CR-M28, CR-M36 | Optimizer maps legal workflow/phase-to-agent edges and preserves roles/gates. Commit summaries use exactly one core reviewer and zero or one ordinary specialist, with required risk escalation and only a directly interacting high-risk second specialist. |
| C-01, C-02, C-10 | Style `applyTo` uses the documented scalar form; model/precedence and validator restrictions are qualified as repository policy, not full CLI/runtime guarantees. |
| C-04, C-05 | Bootstrap discovers existing contracts, preserves canonical capability declarations, and verifies a separate config source root plus required sibling template assets. |
| C-07, C-08, C-15 | Separate handoffs wait for the owning workflow to end; exhaustive review freezes inputs; refactor reports residual coverage risk; no-runner, trivial approval, and personal-preference limits are explicit. |

The scalar `applyTo` conversion preserves each original glob and follows the
[documented path-specific syntax](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions).
It does not establish that sequence syntax previously failed, that templates
without frontmatter were undiscoverable, or that a running CLI loaded new text.
The model catalog is still a historical snapshot; no models were changed.

### Imported Instruction Ownership

The visible `instructions\agent-memory-usage.instructions.md` is an ignored,
untracked regular local copy with no visible generator/do-not-edit contract.
Only its handover prohibition was narrowed: no unsolicited/duplicate per-session
Markdown exports, while truthful existing project/cross-agent record updates and
explicitly required new artifacts remain allowed. Plugin persistence/tool
references remain intact. No external home, private memory, plugin implementation,
or generator was inspected or modified.

This local copy is not a repository-owned distribution of the plugin and must
remain ignored. If the provider regenerates it, the provider-owned requirement
is to retain that same distinction: **forbid duplicate unsolicited session
exports, not maintenance of existing required project/cross-agent records or
explicitly authorized artifacts**. The local edit cannot guarantee future
generator output or tool availability in another/current Copilot home.

### Cross-Surface Integration Contract

Template installation and bootstrap must share one capability owner: a present
project-config declaration is canonical; a root-only declaration must survive
later installation by reference or coordinated migration, with no competing
default-disabled values. Bootstrap's skill-side discovery/tailoring enforces
this interface; template assets and installer behavior have separate owners.
The [bootstrap marker protocol](../../skills/repo-bootstrap/SKILL.md#capability-owner-protocol)
fills `{{DELIVERY_CAPABILITIES_SECTION}}` with the selected
`np-copilot-capabilities-owner` marker and either the owner's verified table or
a non-owner's relative reference. Declaration and references carry the same
marker; only the selected owner has a table. Conflicting explicit ownership or
an existing reference to a missing owner declaration stops before target
mutation, rather than resetting established values or inventing defaults.

The commit-review caller must supply the immutable reviewer intake bundle and
honor missing-evidence responses. Its definition and validator/tests have a
separate owner. Root/README summaries should reference the canonical policies
rather than retain unconditional local-over-project delivery precedence,
guaranteed resolved-model claims, or mandatory one-specialist summaries.

Use the existing configuration and selected review-wording validators for local
source checks. They do not prove active CLI discovery, actual reviewer launches,
external provider behavior, or behavioral outcomes of every described workflow.
No new test framework or runtime integration is introduced.

## Historical Implementation Notes

- The target branch began at `50fac003adc8d6a6f6a9f2a9b9a7d3f8d16aecdb`.
- The earlier hardening run recorded `prompts\Improve-yourself.prompt.md` as
  untracked; the September correction task began with that prompt tracked and
  dirty. Its existing bytes remain outside the correction scope and are preserved.
- Existing local `.copilot` review reports are evidence artifacts and remain untouched.
- Deviations from the locked decisions or protected invariants require a short ADR under `docs\decisions\`.
