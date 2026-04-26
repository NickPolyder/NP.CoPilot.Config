# NP.CoPilot.Config

Global GitHub Copilot CLI configuration — instructions, skills, and agents that apply across all workspaces.

## Structure

```
├── copilot-instructions.md          Global instructions (preferences, personality, workflow)
├── agents/
│   ├── architect.md                 Architecture review agent
│   ├── backend-developer.md         .NET backend specialist
│   ├── code-reviewer.md             Ad-hoc code review agent
│   ├── database-engineer.md         Data modeling & EF Core specialist
│   ├── devops-engineer.md           CI/CD & infrastructure agent
│   ├── frontend-developer.md        Angular/Blazor frontend specialist
│   ├── fullstack-developer.md       End-to-end feature agent
│   ├── product-owner.md             Requirements & user stories agent
│   ├── qa-engineer.md               Test strategy & coverage agent
│   ├── security-engineer.md         Threat modeling & OWASP agent
│   ├── service-fabric-engineer.md   Service Fabric specialist
│   ├── systems-engineer.md          Integration & resilience agent
│   └── ux-engineer.md               User research & design agent
├── skills/
│   ├── architecture-decision-record/
│   │   └── SKILL.md                 Structured ADR creation
│   ├── documentation/
│   │   └── SKILL.md                 Documentation maintenance workflow
│   ├── feature-planning/
│   │   └── SKILL.md                 Multi-agent feature planning with approval gates
│   ├── git-commit-review/
│   │   └── SKILL.md                 Structured commit + 3-hat review workflow
│   ├── prd-workflow/
│   │   └── SKILL.md                 Research → design → tasks → implement chain
│   ├── preflight/
│   │   └── SKILL.md                 Environment & project health check
│   ├── requirement-breakdown/
│   │   └── SKILL.md                 Epic/story breakdown with INVEST criteria
│   ├── retrospective/
│   │   └── SKILL.md                 Post-work reflection & follow-up actions
│   ├── security-audit/
│   │   └── SKILL.md                 STRIDE + OWASP security assessment
│   └── test-strategy/
│       └── SKILL.md                 Test pyramid, edge cases, coverage plan
├── mcps/
│   ├── docker-compose.yml           MCP server stack (SearXNG, Playwright)
│   ├── searxng/
│   │   └── settings.yml             SearXNG engine configuration
│   ├── .env.example                 Environment variable template
│   ├── deploy.ps1                   Deploy stack to remote host via SCP
│   └── README.md                    Quick setup instructions
├── docs/
│   └── mcps.md                      MCP server reference documentation
├── templates/
│   ├── project-config.instructions.md     Per-repo tech stack & build commands
│   ├── local-preferences.instructions.md  Per-user overrides (gitignored)
│   └── gitignore-additions.txt            Gitignore entries for local files
├── mcp-config.json                  MCP client config (symlinked with -Mcp)
├── install.ps1                      Symlinks global config into ~/.copilot/
└── install-project.ps1              Scaffolds templates into a target repo
```

## Installation

### Global config (once)

Symlinks this repo's config into `~/.copilot/` so it loads for every project:

```powershell
.\install.ps1
```

To include MCP server configuration (requires the MCP stack deployed — see [MCP Servers](#mcp-servers)):

```powershell
.\install.ps1 -Mcp
```

To remove:

```powershell
.\install.ps1 -Uninstall
```

### Per-project templates (per repo)

Scaffolds project-specific config into a repo's `.github/instructions/` directory:

```powershell
.\install-project.ps1 -TargetPath C:\Repos\MyProject
```

Then edit the generated files to match your project's tech stack.

## MCP Servers

Self-hosted MCP (Model Context Protocol) servers that extend Copilot CLI with web search and browser automation. The stack runs on a Raspberry Pi and includes SearXNG (search) and Playwright (headless browser).

- **Quick start:** See [`mcps/README.md`](mcps/README.md)
- **Full reference:** See [`docs/mcps.md`](docs/mcps.md)
- **Deploy:** `.\mcps\deploy.ps1` (copies files to Pi and runs `docker compose up -d`)

## How It Works

### Configuration Precedence

| Level | Location | Scope |
|---|---|---|
| **Global** | `~/.copilot/` | Your preferences, agents, skills — always active |
| **Project** | `.github/instructions/*.instructions.md` | Repo-specific: framework, build commands, feature toggles |
| **Local** | `.github/instructions/local-preferences.instructions.md` | Personal overrides, gitignored |

Global loads first. Project config extends it. Local preferences layer on top.

### Symlinks

Copilot CLI reads config from `~/.copilot/`. Rather than copying files there, `install.ps1` symlinks them so changes stay version-controlled.

| Item | Symlink Source | Symlink Target |
|---|---|---|
| Instructions | `copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| Agents | `agents/` | `~/.copilot/agents/` |
| Skills | `skills/` | `~/.copilot/skills/` |
| MCP Config | `mcp-config.json` | `~/.copilot/mcp-config.json` *(opt-in with `-Mcp`)* |

## Overriding Per-Repo

Repository-level config (`.github/copilot-instructions.md`, `.github/instructions/`, `.github/agents/`, `.github/skills/`) takes precedence over global config. Use repo-level overrides when a project needs different behaviour.

## Skills Quick Reference

| Skill | When to Use |
|---|---|
| `prd-workflow` | Build something from scratch: research → design → tasks → implement |
| `feature-planning` | Plan a feature across all domains (UX, arch, security, deployment) |
| `requirement-breakdown` | Break an epic into user stories with acceptance criteria |
| `git-commit-review` | Pre-commit code review with 3-hat + specialist reviewers |
| `test-strategy` | Design test coverage for a feature or code change |
| `security-audit` | STRIDE threat model + OWASP checklist assessment |
| `architecture-decision-record` | Capture a significant architectural decision |
| `documentation` | Create or update project documentation |
| `preflight` | Verify environment and project health before starting work |
| `retrospective` | Reflect on completed work — what went well, what to improve |
