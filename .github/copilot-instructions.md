# Copilot Instructions — NP.CoPilot.Config

## What This Repo Is

A **global GitHub Copilot CLI configuration** repository. It defines instructions, agents, skills, MCP server infrastructure, and installer scripts that apply across all workspaces via symlinks into `~/.copilot/`.

This is not a typical code project — there are no build/test/lint pipelines. The deliverables are markdown definitions and PowerShell scripts.

## Architecture

```
copilot-instructions.md    → Root operating contract (symlinked to ~/.copilot/)
instructions/*.instructions.md → Canonical policies (coordination, workflow, lifecycle, delivery, style)
agents/*.md                → Specialist agent definitions (17 agents)
skills/*/SKILL.md          → Focused workflows (25 skills)
mcps/                      → MCP integration support (remote Docker Compose: SearXNG only)
templates/                 → Per-repo scaffolding templates (Generic, Angular, Blazor, Service Fabric) + repo-bootstrap/ (agent contract + docs memory tree)
mcp-config.json            → MCP client config for SearXNG bridge + local Playwright
install.ps1                → Symlinks this repo into ~/.copilot/ (core install script)
install-project.ps1        → Scaffolds project-level templates into a target repo (-Template param)
mcps/deploy.ps1            → Deploys MCP Docker stack (Remote/Local/WSL modes)
```

### Configuration Conflict Resolution (important for understanding scope)

Copilot combines applicable guidance from all of these sources:

1. **Global** (`~/.copilot/`) — this repo's content, always active
2. **Project** (`.github/instructions/*.instructions.md`) — repository-specific guidance
3. **Local** (gitignored per-user files) — personal preferences

When combined guidance conflicts, use the most repository-specific instruction unless a higher-priority system or safety constraint prevents it.

## Key Conventions

### Agent Definitions (`agents/*.md`)

- Each file defines one specialist agent with a focused domain (architect, backend-dev, QA, etc.)
- Agents use tools (edit, search, commands) but **never** invoke orchestrator skills directly
- If an agent identifies work needing a skill, it recommends it to the user instead

### Skill Definitions (`skills/*/SKILL.md`)

- Each skill is a multi-step orchestration workflow with approval gates
- Skills coordinate with agents for domain expertise
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
- `deploy.ps1` supports three modes: Remote (SSH/SCP), Local, WSL

### MCP Stack

- Runs pinned SearXNG (search) as the remote Docker container; Playwright runs locally as a pinned stdio MCP process
- Default target: Raspberry Pi at `raspberrypi` / `192.168.1.2`
- `mcp-config.json` merge logic: existing entries win on conflict, backup is created

### Templates (`templates/`)

- `project-config.instructions.md` — fill-in-the-blanks tech stack + build commands
- `local-preferences.instructions.md` — per-user overrides (always gitignored)
- `gitignore-additions.txt` — entries appended to target repo's `.gitignore`

## Working in This Repo

- Changes to `copilot-instructions.md`, `agents/`, or `skills/` take effect immediately in any Copilot CLI session (they're symlinked)
- Test install scripts with `-WhatIf` where supported (`deploy.ps1`) or by inspecting symlink targets
- The `mcps/` stack requires Docker and a deployed host — see `mcps/README.md` for setup
