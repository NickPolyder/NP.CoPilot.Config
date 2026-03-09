# NP.CoPilot.Config

Global GitHub Copilot CLI configuration — instructions, skills, and agents that apply across all workspaces.

## Structure

```
├── copilot-instructions.md          Global instructions (personal preferences)
├── agents/
│   ├── code-reviewer.md             Code review agent
│   └── architect.md                 Architecture review agent
├── skills/
│   ├── git-commit-review/
│   │   └── SKILL.md                 Structured commit + 3-hat review workflow
│   └── documentation/
│       └── SKILL.md                 Documentation maintenance workflow
└── install.ps1                      Symlinks config into ~/.copilot/
```

## Installation

Run the install script to create symlinks from `~/.copilot/` to this repo:

```powershell
.\install.ps1
```

To remove the symlinks:

```powershell
.\install.ps1 -Uninstall
```

## How It Works

Copilot CLI reads configuration from `~/.copilot/`. Rather than copying files there, this repo symlinks them so changes are version-controlled.

| Item | Symlink Source | Symlink Target |
|---|---|---|
| Instructions | `copilot-instructions.md` | `~/.copilot/copilot-instructions.md` |
| Agents | `agents/` | `~/.copilot/agents/` |
| Skills | `skills/` | `~/.copilot/skills/` |

## Overriding Per-Repo

Repository-level config (`.github/copilot-instructions.md`, `.github/skills/`, `.github/agents/`) takes precedence over global config. Use repo-level overrides when a project needs different behaviour.
