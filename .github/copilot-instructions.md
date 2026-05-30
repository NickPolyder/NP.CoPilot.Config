# Copilot Instructions — NP.CoPilot.Config

## What This Repo Is

A **global GitHub Copilot CLI configuration** repository. It defines instructions, agents, skills, MCP server infrastructure, and installer scripts that apply across all workspaces via symlinks into `~/.copilot/`.

This is not a typical code project — there are no build/test/lint pipelines. The deliverables are markdown definitions and PowerShell scripts.

## Architecture

```
copilot-instructions.md    → Root instructions (quick reference, symlinked to ~/.copilot/)
instructions/*.instructions.md → Split instruction files (personality, workflow, git, etc.)
agents/*.md                → Specialist agent definitions (15 agents)
skills/*/SKILL.md          → Multi-step orchestration workflows (15 skills)
mcps/                      → Self-hosted MCP server stack (Docker Compose: SearXNG + Playwright)
templates/                 → Per-repo scaffolding templates (Generic, Angular, Blazor, Service Fabric)
mcp-config.json            → MCP client config pointing at SearXNG + Playwright endpoints
install.ps1                → Symlinks this repo into ~/.copilot/ (core install script)
install-project.ps1        → Scaffolds project-level templates into a target repo (-Template param)
mcps/deploy.ps1            → Deploys MCP Docker stack (Remote/Local/WSL modes)
```

### Configuration Precedence (important for understanding scope)

1. **Global** (`~/.copilot/`) — this repo's content, always active
2. **Project** (`.github/instructions/*.instructions.md`) — repo-specific overrides
3. **Local** (gitignored per-user files) — personal preferences

## Key Conventions

### Agent Definitions (`agents/*.md`)

- Each file defines one specialist agent with a focused domain (architect, backend-dev, QA, etc.)
- Agents use tools (edit, search, commands) but **never** invoke orchestrator skills directly
- If an agent identifies work needing a skill, it recommends it to the user instead

### Skill Definitions (`skills/*/SKILL.md`)

- Each skill is a multi-step orchestration workflow with approval gates
- Skills coordinate with agents for domain expertise
- Orchestrator skills (`prd-workflow`, `feature-planning`, `git-commit-review`) must never nest inside each other

### Invocation Hierarchy (strict)

```
User → Skill → Agent → Tools
```

No level may call upward. No orchestrator may nest inside another orchestrator.

### PowerShell Scripts

- All scripts use `$ErrorActionPreference = 'Stop'`
- Use emoji-based `Write-Status` helper for consistent console output
- Scripts are idempotent — safe to re-run
- `install.ps1` supports `-Mcp` (opt-in) and `-Uninstall` switches
- `deploy.ps1` supports three modes: Remote (SSH/SCP), Local, WSL

### MCP Stack

- Runs SearXNG (search) and Playwright (browser) as Docker containers
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
