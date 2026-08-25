# NP.CoPilot.Config

Global GitHub Copilot CLI configuration — instructions, skills, and agents that apply across all workspaces.

## Structure

```
├── copilot-instructions.md          Root operating contract (loads first)
├── instructions/
│   ├── personality.instructions.md  Identity, tone, communication style (always loaded)
│   ├── communication-writing.instructions.md  Reader-first email, post, and article structure (always loaded)
│   ├── workflow.instructions.md     Tiered dev workflow: Trivial/Standard/Full (always loaded)
│   ├── work-lifecycle.instructions.md  Atomic outcomes, blockers, and capability-gated delivery (always loaded)
│   ├── git-conventions.instructions.md  Delivery and commit safety (always loaded)
│   ├── session-awareness.instructions.md  Start/end session behavior (always loaded)
│   ├── coordination.instructions.md      Skill hierarchy, agent handoff format (always loaded)
│   ├── csharp-style.instructions.md      C# conventions (applyTo: *.cs)
│   ├── powershell-style.instructions.md  PowerShell conventions (applyTo: *.ps1)
│   ├── python-style.instructions.md      Python conventions (applyTo: *.py)
│   ├── typescript-style.instructions.md  TypeScript/Node conventions (applyTo: *.ts, *.js)
│   ├── sql-style.instructions.md         SQL conventions (applyTo: *.sql)
│   ├── markdown-style.instructions.md    Docs conventions (applyTo: docs/**/*.md)
│   └── yaml-docker-style.instructions.md YAML/Docker conventions (applyTo: *.yml, Dockerfile)
├── agents/
│   ├── architect.md                 Architecture review agent
│   ├── backend-developer.md         .NET backend specialist
│   ├── code-reviewer.md             Ad-hoc code review agent
│   ├── database-engineer.md         Data modeling & EF Core specialist
│   ├── devops-engineer.md           CI/CD & infrastructure agent
│   ├── frontend-developer.md        Angular/Blazor frontend specialist
│   ├── fullstack-developer.md       End-to-end feature agent
│   ├── node-developer.md            Node/TypeScript & Next.js specialist (small apps)
│   ├── product-owner.md             Requirements & user stories agent
│   ├── python-developer.md          Python, MCP servers & FastAPI specialist
│   ├── qa-engineer.md               Test strategy & coverage agent
│   ├── security-engineer.md         Threat modeling & OWASP agent
│   ├── service-fabric-engineer.md   Service Fabric specialist
│   ├── systems-engineer.md          Integration & resilience agent
│   ├── technical-writer.md          Documentation craft specialist
│   ├── test-engineer.md             Deterministic unit-test specialist
│   └── ux-engineer.md               User research & design agent
├── skills/
│   ├── architecture-decision-record/
│   │   └── SKILL.md                 Structured ADR creation
│   ├── codebase-research/
│   │   └── SKILL.md                 Read-only codebase research
│   ├── dependency-audit/
│   │   └── SKILL.md                 Package vulnerability & update audit
│   ├── dependency-audit-report/
│   │   └── SKILL.md                 Read-only dependency audit report
│   ├── dependency-upgrade-execution/
│   │   └── SKILL.md                 Approved dependency upgrade execution
│   ├── documentation/
│   │   └── SKILL.md                 Documentation maintenance workflow
│   ├── feature-planning/
│   │   └── SKILL.md                 Multi-agent feature planning with approval gates
│   ├── feature-design-doc/
│   │   └── SKILL.md                 Feature design document generation
│   ├── git-commit-review/
│   │   └── SKILL.md                 Lightweight staged pre-commit review workflow
│   ├── implementation-runner/
│   │   └── SKILL.md                 Approved task implementation
│   ├── full-code-review/
│   │   └── SKILL.md                 Explicit exhaustive multi-hat review workflow
│   ├── prd-workflow/
│   │   └── SKILL.md                 Research → design → tasks → implement chain
│   ├── preflight/
│   │   └── SKILL.md                 Environment & project health check
│   ├── refactor/
│   │   └── SKILL.md                 Safety-first refactoring with test verification
│   ├── repo-bootstrap/
│   │   └── SKILL.md                 Bootstrap a repo's agent contract + docs memory tree
│   ├── requirement-breakdown/
│   │   └── SKILL.md                 Epic/story breakdown with INVEST criteria
│   ├── resume/
│   │   └── SKILL.md                 Session context recovery
│   ├── retrospective/
│   │   └── SKILL.md                 Post-work reflection & follow-up actions
│   ├── scaffold/
│   │   └── SKILL.md                 Code generation for common patterns
│   ├── security-audit/
│   │   └── SKILL.md                 STRIDE + OWASP security assessment
│   ├── task-breakdown/
│   │   └── SKILL.md                 Dependency-aware task generation
│   ├── test-gap-analysis/
│   │   └── SKILL.md                 Retroactive test coverage audit
│   ├── test-gap-audit/
│   │   └── SKILL.md                 Read-only test-gap audit
│   ├── test-gap-fill/
│   │   └── SKILL.md                 Approved test-gap implementation
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
│   ├── agent-coordination.md        Agent handoff protocol (design reference)
│   ├── model-selection.md           Which AI model to use for which work, and why
│   ├── features/                    Feature exploration docs
│   └── mcps.md                      MCP server reference documentation
├── templates/
│   ├── project-config.instructions.md              Generic per-repo template
│   ├── project-config-angular.instructions.md      Angular + .NET API template
│   ├── project-config-blazor.instructions.md       Blazor + .NET template
│   ├── project-config-service-fabric.instructions.md  Service Fabric template
│   ├── local-preferences.instructions.md           Per-user overrides (gitignored)
│   ├── gitignore-additions.txt                     Gitignore entries for local files
│   └── repo-bootstrap/                             Agent contract + docs memory templates (repo-bootstrap skill)
├── mcp-config.json                  MCP client config (symlinked with -Mcp)
├── install.ps1                      Symlinks global config into ~/.copilot/
└── install-project.ps1              Scaffolds templates into a target repo (-Template Angular|Blazor|ServiceFabric)
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

## Validation

Run the repository-owned structural validation before proposing configuration
changes for review:

```powershell
pwsh -NoProfile -File .\scripts\Validate-Config.ps1
```

The validator is read-only. It validates frontmatter, references, workflow
composition, README inventory, runtime version pins and documented waivers, MCP JSON, Compose syntax,
and review capability boundaries. The regression suite remains independently
runnable with `pwsh -NoProfile -File .\tests\ValidateConfig\Run-ValidateConfigTests.ps1`.

Enable the repository pre-commit hook to validate staged configuration changes
against an index-only snapshot:

```powershell
git config core.hooksPath .githooks
```

The hook runs only when staged paths include Copilot configuration or its
validator. It never reads unstaged worktree changes.

## MCP Servers

MCP (Model Context Protocol) integrations extend Copilot CLI with web search and browser automation. The remote Raspberry Pi stack runs pinned SearXNG; Playwright MCP runs locally on the workstation over stdio from the user-approved `@latest` package channel.

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

Copilot combines applicable guidance from every level. When the guidance conflicts, agents should follow the most repository-specific instruction unless a higher-priority system or safety constraint prevents it.

### Operating Model

The global configuration governs **how** work is performed: verified atomic outcomes, proportionate workflow, user control, and repository-policy compliance.
Each repository defines **why** it exists—its mission, users, domain constraints, and delivery capabilities—in project-level instructions.

Cross-cutting policy has one canonical owner:

| Concern | Owner |
|---|---|
| Precedence, delegation, handoffs | `instructions/coordination.instructions.md` |
| Work tiers and proportional verification | `instructions/workflow.instructions.md` |
| Ownership, blockers, outcome verification, optional capabilities | `instructions/work-lifecycle.instructions.md` |
| Delivery path, protected branches, commit approvals | `instructions/git-conventions.instructions.md` |
| Session continuity | `instructions/session-awareness.instructions.md` |

Repositories opt into issue tracking, isolated worktrees, protected branches, integration queues, and deployment evidence through the `Agent Delivery Capabilities` table in their project configuration.
Absent or disabled capabilities add no process requirements.

### Symlinks

Copilot CLI reads config from `~/.copilot/`. Rather than copying files there, `install.ps1` symlinks them so changes stay version-controlled.

| Item | Symlink Source | Symlink Target |
|---|---|---|
| Root Instructions | `copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| Instructions Folder | `instructions/` | `~/.copilot/instructions/` |
| Agents | `agents/` | `~/.copilot/agents/` |
| Skills | `skills/` | `~/.copilot/skills/` |
| MCP Config | `mcp-config.json` | `~/.copilot/mcp-config.json` *(opt-in with `-Mcp`)* |

## Overriding Per-Repo

Repository-level config (`.github/copilot-instructions.md`, `.github/instructions/`, `.github/agents/`, `.github/skills/`) provides the more repository-specific guidance when combined instructions conflict. Use it when a project needs different behaviour.

## Skills Quick Reference

| Skill | When to Use |
|---|---|
| `prd-workflow` | Build something from scratch: research → design → tasks → implement |
| `codebase-research` | Read an existing codebase before designing a feature |
| `feature-design-doc` | Turn grounded research into a feature design document |
| `task-breakdown` | Convert an approved design into dependency-aware tasks |
| `implementation-runner` | Execute an approved task breakdown in dependency order |
| `feature-planning` | Plan a feature across all domains (UX, arch, security, deployment) |
| `requirement-breakdown` | Break an epic into user stories with acceptance criteria |
| `git-commit-review` | Fast pre-commit review of one staged atomic candidate |
| `full-code-review` | Explicit exhaustive review for release candidates and high-risk changes |
| `scaffold` | Generate boilerplate for common patterns (service, aggregate, endpoint) |
| `refactor` | Structured refactoring with test verification at each step |
| `repo-bootstrap` | Bootstrap a repo for agent-driven work: agent contract + docs memory tree |
| `test-strategy` | Design test coverage for a feature or code change |
| `test-gap-analysis` | Audit existing code for untested paths and weak assertions |
| `test-gap-audit` | Produce a read-only risk-prioritized test-gap report |
| `test-gap-fill` | Generate approved tests for identified gaps |
| `dependency-audit` | Check for outdated/vulnerable packages and upgrade safely |
| `dependency-audit-report` | Produce a read-only dependency risk report |
| `dependency-upgrade-execution` | Execute approved dependency upgrades in safe batches |
| `security-audit` | STRIDE threat model + OWASP checklist assessment |
| `architecture-decision-record` | Capture a significant architectural decision |
| `documentation` | Create or update project documentation |
| `preflight` | Verify environment and project health before starting work |
| `resume` | Recover context from previous sessions — continue where you left off |
| `retrospective` | Reflect on completed work — what went well, what to improve |
