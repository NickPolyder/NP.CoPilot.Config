# Copilot Configuration Hardening

**Status:** Follow-up corrections locally verified; changes await user review. Active-installation adoption remains unverified.

## Purpose

Harden the global Copilot configuration without replacing its existing operating model.
The work addresses the configuration review completed on 2026-08-25: capability enforcement, installer recovery, MCP architecture, policy precision, structural validation, and documentation drift.

## Locked Decisions

| Area | Decision |
|---|---|
| Scope | Address all review findings in dependency-ordered phases. |
| Playwright | Run local `@playwright/mcp@latest` under the existing user-approved mutable-version waiver; the remote Playwright service and port remain removed. |
| Hooks | Defer native hooks until the core controls have proved stable. |
| AgentMemory | Keep the plugin as the only owner of its instruction, skill, and MCP integration. |
| Review reports | Review workflows persist reports; `code-reviewer` returns findings only. |
| Skill metadata | Remove inert frontmatter metadata; do not replace it with permissive `allowed-tools`. |
| Context | Measure before trimming and preserve intent and final-rule anchors. |

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

## Implementation Notes

- The target branch began at `50fac003adc8d6a6f6a9f2a9b9a7d3f8d16aecdb`.
- `prompts\Improve-yourself.prompt.md` was untracked before work began and is outside this change.
- Existing local `.copilot` review reports are evidence artifacts and remain untouched.
- Deviations from the locked decisions or protected invariants require a short ADR under `docs\decisions\`.
