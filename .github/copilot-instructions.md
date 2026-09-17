# Copilot Instructions — NP.CoPilot.Config

## What This Repo Is

A **global GitHub Copilot CLI configuration** repository. It defines instructions,
agents, skills, MCP server infrastructure, and installer scripts shared across
workspaces when installed and loaded from the selected Copilot home (normally
`~/.copilot/`).

This is not a typical code project — there are no build/test/lint pipelines, but repository-owned local validators and isolated regression suites exist. The deliverables are markdown definitions and PowerShell scripts.

## Architecture

```
copilot-instructions.md    → Root operating contract (symlinked to the selected Copilot home)
instructions/*.instructions.md → Canonical policies (coordination, workflow, lifecycle, delivery, style)
agents/*.md                → Three role cards: investigator, implementer, code-reviewer
skills/*/SKILL.md          → Focused workflows and atomic skills (26 skills)
skills/domain-guidance.md  → On-demand domain notes, not an additional skill
mcps/                      → MCP integration support (remote Docker Compose: SearXNG only)
scripts/                   → Local validators, raw-tree snapshot helpers, and checked Git-hook setup
tests/                     → Isolated installer, deployment, validator, and snapshot regression suites
templates/                 → Per-repo scaffolding templates (Generic, Angular, Blazor, Service Fabric) + repo-bootstrap/ (agent contract + docs memory tree)
mcp-config.json            → MCP client config for SearXNG bridge + local Playwright
install.ps1                → Symlinks this repo into the selected Copilot home (core install script)
install-project.ps1        → Scaffolds project-level templates into a target repo (-Template param)
mcps/deploy.ps1            → Deploys MCP Docker stack (Remote/Local/WSL modes)
```

### Configuration Conflict Resolution (important for understanding scope)

Copilot combines applicable guidance from all of these sources:

1. **Global** (selected Copilot home) — this repo's shared defaults when installed and loaded
2. **Project** (`.github/instructions/*.instructions.md`) — repository-specific guidance
3. **Local** (gitignored per-user files) — personal preferences

Use the canonical conflict policy in `instructions\coordination.instructions.md`.
Personal preferences cannot waive project ownership, required evidence,
approvals, or delivery controls; higher-priority safety constraints remain.

## Key Conventions

### Agent Definitions (`agents/*.md`)

- Prefer direct work; delegate only bounded assignments that benefit from separate context or satisfy required review.
- Select by activity: investigator for read-only analysis, implementer for approved changes, code-reviewer for independent immutable-input review.
- Supply only relevant domain notes. Required domain reviews remain separate assignments even when they share a role card.
- Agents are terminal: use permitted tools, return additional needs to the caller, and never invoke skills or spawn agents.

### Skill Definitions (`skills/*/SKILL.md`)

- Skills are entry workflows, thin coordinators, atomic phases or terminal workflows; use only documented composition.
- Small work does not require a workflow or agent solely because a matching definition exists.
- Orchestrator skills (`prd-workflow`, `feature-planning`, `git-commit-review`, `full-code-review`) must never nest inside each other

### Skill Composition (bounded)

```
User → one entry workflow or atomic skill → atomic phase skills → Agent → Tools
```

Only one entry workflow may be active. Entry workflows and thin coordinators may sequence their documented atomic skills; atomic skills never invoke entry workflows or coordinators. A completed workflow may hand off to a separate terminal workflow such as `git-commit-review`; this is not nesting.

### PowerShell Scripts

- All scripts use `$ErrorActionPreference = 'Stop'`
- Use emoji-based `Write-Status` helper for consistent console output
- Scripts are idempotent — safe to re-run
- `install.ps1` supports `-Mcp` (opt-in) and `-Uninstall` switches
- `install.ps1` also supports `-Status` and remaining-scope `-Repair`; explicit `-TargetRoot` overrides `COPILOT_HOME`, then the normal home default
- `deploy.ps1` supports three modes: Remote (SSH stdin), Local, WSL; private environment provisioning and key rotation are explicit

### MCP Stack

- Runs pinned SearXNG (search) as the remote Docker container; Playwright runs locally as a stdio MCP process under the existing user-approved `@latest` waiver
- Default target: Raspberry Pi at `raspberrypi` / `192.168.1.2`
- `mcp-config.json` merge logic: existing entries win on conflict, backup is created

### Templates (`templates/`)

- `project-config.instructions.md` — fill-in-the-blanks tech stack + build commands
- `local-preferences.instructions.md` — per-user preferences protected by the normal managed-ignore path; `-SkipGitignore` requires manual protection
- `gitignore-additions.txt` — manual exclusion recipe; installer tracks actual rule ownership and Git effectiveness separately
- Delivery capabilities have one declaring owner and matching owner-marker references; refresh/Force must not replace verified values with competing defaults
- Bootstrap resolves its configuration source and sibling assets explicitly; external plugin provenance or preserved backups do not prove runtime discovery
- Project installation requires both source templates and target-bound valid state; Force cannot bypass ownership, recovery, or path-conflict guards
- Project uninstall preserves pending restoration and necessary personal/recovery exclusions; retry after resolving the reported failure rather than deleting state

## Working in This Repo

- Changes to `copilot-instructions.md`, `agents/`, or `skills/` update symlinked disk content; do not assume an already-running session has reloaded that content.
- Keep the root plus six owned unscoped policies within the 1,000–1,500-word target; do not count or rewrite the externally owned memory-plugin instruction as local policy.
- Validate configuration with `pwsh -NoProfile -File .\scripts\Validate-Config.ps1`; use `scripts\Validate-GitCommitReviewSkills.ps1` for the selected review-policy wording checks.
- `scripts\README.md` defines strict validation scope, helper/assets dependencies, and platform limits; model/tool restrictions are repository policy, not all CLI capabilities
- Exact commit-review evidence binds base/tree/ordered parents/ref state/destination and tracked snapshot bytes; use the target repository's declared checks, not an assumed downstream copy of this validator
- Opt-in hook setup uses `pwsh -NoProfile -File .\scripts\Enable-ConfigGitHook.ps1`; do not activate the current checkout merely to test changes. The tracked launcher remains `100644`, and fresh POSIX checkouts require per-checkout setup
- Run the relevant isolated suite: `tests\Install\Run-InstallTests.ps1`, `tests\InstallProject\Run-InstallProjectTests.ps1`, or `tests\ValidateConfig\Run-ValidateConfigTests.ps1`, each via `pwsh -NoProfile -File`. Do not test installer changes against the active user installation.
- For commit-review changes, run `tests\GitCommitReviewSkill\Run-GitCommitReviewSkillTests.ps1` and `tests\GitCommitReviewSkill\Run-GitSnapshotProcedureTests.ps1` via `pwsh -NoProfile -File`.
- For deployment changes, run `pwsh -NoProfile -File .\tests\Deploy\Run-DeployTests.ps1`; target commands are intercepted and no deployed host/private key is required
- Actual MCP use has integration- and mode-specific Docker, Node/npm, host, and routing prerequisites — see `mcps/README.md`; syntax checks are not readiness or live-runtime evidence
