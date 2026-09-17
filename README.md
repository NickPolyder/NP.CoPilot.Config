# NP.CoPilot.Config

Reusable global GitHub Copilot CLI configuration — instructions, skills, and agents
that apply when installed and loaded from the selected Copilot home.

## Structure

```
├── copilot-instructions.md          Root operating contract
├── instructions/
│   ├── personality.instructions.md  User-selected tone, initiative and technical preferences (unscoped)
│   ├── workflow.instructions.md     Proportional process and stopping conditions (unscoped)
│   ├── work-lifecycle.instructions.md  Atomic outcomes, blockers, and capability-gated delivery (unscoped)
│   ├── git-conventions.instructions.md  Delivery and commit safety (unscoped)
│   ├── session-awareness.instructions.md  Start/end session behavior (unscoped)
│   ├── coordination.instructions.md      Policy precedence, bounded roles and composition (unscoped)
│   ├── csharp-style.instructions.md      C# conventions (applyTo: *.cs)
│   ├── powershell-style.instructions.md  PowerShell conventions (applyTo: *.ps1)
│   ├── python-style.instructions.md      Python conventions (applyTo: *.py)
│   ├── typescript-style.instructions.md  TypeScript/Node conventions (applyTo: *.ts, *.js)
│   ├── sql-style.instructions.md         SQL conventions (applyTo: *.sql)
│   ├── markdown-style.instructions.md    Docs conventions (applyTo: docs/**/*.md)
│   └── yaml-docker-style.instructions.md YAML/Docker conventions (applyTo: *.yml, Dockerfile)
├── agents/
│   ├── investigator.md             Read-only research, diagnosis and design
│   ├── implementer.md              Bounded code, test, documentation and config changes
│   └── code-reviewer.md             Independent immutable-input review; read/search only
├── skills/
│   ├── domain-guidance.md          On-demand domain notes, not a skill
│   ├── architecture-decision-record/
│   │   └── SKILL.md                 Structured ADR creation
│   ├── codebase-research/
│   │   └── SKILL.md                 Read-only codebase research
│   ├── communication-writing/
│   │   └── SKILL.md                 Requested email, post and article drafting
│   ├── dependency-audit/
│   │   └── SKILL.md                 Package vulnerability & update audit
│   ├── dependency-audit-report/
│   │   └── SKILL.md                 Read-only dependency audit report
│   ├── dependency-upgrade-execution/
│   │   └── SKILL.md                 Approved dependency upgrade execution
│   ├── documentation/
│   │   └── SKILL.md                 Documentation maintenance workflow
│   ├── feature-planning/
│   │   └── SKILL.md                 Explicit feature planning with approval gates
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
│   ├── docker-compose.yml           Remote SearXNG service (no remote browser)
│   ├── searxng/
│   │   └── settings.yml             SearXNG engine configuration
│   ├── .env.example                 Environment variable template
│   ├── Initialize-Environment.ps1   Private environment provisioning and explicit rotation
│   ├── deploy.ps1                   Deploy in Remote, Local, or WSL mode
│   ├── Mcp.Deployment.psm1          Deployment transport and readiness helpers
│   └── README.md                    Quick setup instructions
├── docs/
│   ├── agent-coordination.md        Agent handoff protocol (design reference)
│   ├── model-selection.md           Which AI model to use for which work, and why
│   ├── features/                    Feature exploration docs
│   └── mcps.md                      MCP server reference documentation
├── scripts/
│   ├── Validate-Config.ps1          Structural definition and runtime-reference checks
│   ├── Validate-GitCommitReviewSkills.ps1  Selected review-policy wording checks
│   ├── GitSnapshot.psm1             Raw-tree materialization and exact-candidate guards
│   ├── IsolatedProcess.psm1         Controlled child homes and Git environments
│   ├── ConfigurationParsing.psm1    Strict repository YAML-subset parser
│   ├── Invoke-ConfigPreCommitHook.ps1  Captured-index validation driver
│   ├── Enable-ConfigGitHook.ps1     Checked opt-in hook setup
│   └── README.md                    Helper, input-domain, and platform contracts
├── .githooks/
│   └── pre-commit                   Git hook launcher, not a Copilot lifecycle hook
├── tests/                          Isolated installer, deployment, and validation suites
├── templates/
│   ├── project-config.instructions.md              Generic per-repo template
│   ├── project-config-angular.instructions.md      Angular + .NET API template
│   ├── project-config-blazor.instructions.md       Blazor + .NET template
│   ├── project-config-service-fabric.instructions.md  Service Fabric template
│   ├── local-preferences.instructions.md           Per-user overrides (gitignored)
│   ├── gitignore-additions.txt                     Gitignore entries for local files
│   └── repo-bootstrap/                             Agent contract + docs memory templates (repo-bootstrap skill)
├── mcp-config.json                  MCP client config (linked or merged with -Mcp)
├── install.ps1                      Installs into the selected Copilot home
└── install-project.ps1              Scaffolds templates into a target repo (-Template Angular|Blazor|ServiceFabric)
```

## Lean operating model

The root and six owned unscoped policies target 1,000–1,500 whitespace-delimited
words combined; scoped styles and the externally owned memory-plugin instruction
are separate. Ordinary work stays direct and bounded. Explicit workflows retain
their required artifacts and gates; several changed files alone do not require
a tier label, planning document, retrospective or specialist chain.

There are **3 role cards and 26 skills**. The caller selects only relevant
[domain notes](skills/domain-guidance.md), not an entire agent textbook. Required
domain reviews use separate focused reviewer assignments; sharing a role card
does not merge their independent scopes or relax reviewer counts.
Communication writing is on demand rather than loaded as ordinary chat policy.
The personality file records the user's Q&A choices, not a fictional persona.

This is a configuration-size and routing change, not measured proof of better
model performance. File edits do not prove a running session reloaded them or
which model/source it resolved. Compare task outcomes in a fresh, authorized
session before attributing speed or quality changes to the rewrite.

## Installation

### Global config (once)

Requires PowerShell 7+ and permission to create symbolic links (Windows Developer
Mode or elevation). The installer selects an explicit `-TargetRoot` first, then
`COPILOT_HOME` when set, otherwise `$HOME\.copilot`. Relative targets are
normalized before ownership is recorded:

```powershell
.\install.ps1
```

To manage a different home explicitly:

```powershell
.\install.ps1 -TargetRoot 'H:\CopilotProfiles\work'
.\install.ps1 -TargetRoot 'H:\CopilotProfiles\work' -Status
```

To include MCP client configuration (runtime prerequisites and endpoint setup
are described in [MCP Servers](#mcp-servers)):

```powershell
.\install.ps1 -Mcp
```

An absent MCP file becomes a symlink; an existing ordinary file is merged with
per-entry ownership. Existing user entries win, including coincidental matches.
Unchanged owned entries refresh or retire with the source; customized entries
remain explicit conflicts. Hard-linked merge files and unexpected replacement
links are refused rather than writing through another owner's filename.
MCP parsing accepts strict JSON with unique case-insensitive object keys and
nesting up to 100 levels; unsupported documents fail before mutation. Date-like
strings, numeric tokens, nested arrays, and user metadata are preserved rather
than coerced or truncated during reconciliation.

To inspect, repair the still-tracked scope, preview, or remove:

```powershell
.\install.ps1 -Status
.\install.ps1 -Repair
.\install.ps1 -Uninstall -WhatIf
.\install.ps1 -Uninstall
```

Use the same home selector for each command. Status inspects live links and MCP
content without printing configuration bodies or secrets. Source and target
directories must not overlap or use linked directory ancestry. Manifest target,
artifact paths, and recovery paths are validated before mutation; corrupt,
unreadable, unsupported, or relocated state is not treated as a fresh install.
Supported version-one manifests are upgraded without discarding restore points.

Installation/repair retain their rollback boundary. Uninstall is recoverable
but is not an all-or-nothing transaction: drifted content remains with explicit
guidance, and successfully removed artifacts are not recreated by a later
partial-scope repair. Earlier originals and unconsumed recovery material remain
under `.np-copilot-installer\backups` rather than being silently deleted.
Inspect retained backups before explicitly disposing of them. Missing restore
points or cleanup failures are errors, not success-shaped fallbacks.
Restoration records its intent and original fingerprint before moving a backup,
then persists each completed artifact separately. A later failure or failed
completion publication can therefore resume with `-Uninstall`; status identifies
pending recovery, and install/repair refuse to overwrite it. If a restored
original changes before retry, it is preserved for explicit reconciliation.

Moving a home or source does not automatically migrate its manifest. Preserve
the recorded state and originals, resolve the old installation deliberately,
and then install into the newly selected location. Do not repair a corrupt
manifest by deleting it and reinstalling over forgotten backups.

### Per-project templates (per repo)

Scaffolds project-specific config into a repo's `.github/instructions/` directory:

```powershell
.\install-project.ps1 -TargetPath C:\Repos\MyProject
```

Then edit the generated files to match your project's tech stack.

The target must be a Git repository. Both selected source templates are required
before mutation. The installer normalizes the target, validates its bound
ownership manifest and recovery paths, and refuses corrupt, unreadable, copied,
or unsupported state even with `-Force`. Supported legacy manifests migrate
without discarding originals. Directory collisions and linked target/state
ancestry are not treated as permission to overwrite arbitrary content.

An identical pre-existing file is still foreign unless previously managed or
explicitly adopted with preservation-safe `-Force`. Existing capability values
and their single declaring owner survive template variant changes and refreshes.
Uninstall checkpoints restoration and retains pending recovery after failures;
retry `-Uninstall` after resolving the reported lock or conflict. Recovery
copies and earlier originals are not silently discarded. Hard-linked originals
retain recoverable bytes, not a guarantee of recreating their alias relationships.

The normal managed-ignore path protects live personal preferences and installer
state/backups. Exclusions remain necessary while edited personal files or
recovery material survive uninstall. Rule effectiveness is checked with Git
separately from whether this installer inserted or owns the rule. `-SkipGitignore`
explicitly leaves that protection to you; use `templates\gitignore-additions.txt`
as the manual recipe. Already tracked private artifacts are reported rather
than silently removed from the index.

## Validation

Run the repository-owned structural validation before proposing configuration
changes for review:

```powershell
pwsh -NoProfile -File .\scripts\Validate-Config.ps1
```

The validator is read-only. It checks required definition fields with a strict
repository YAML subset, references, a declared orchestration map, README
inventory entries, explicit runtime versions/digests and documented waivers,
MCP JSON, optional Compose syntax, and selected review capability rules.
Its documented on-disk agent/skill domain includes hidden, ignored, and
untracked definitions; linked inputs and unsupported layouts fail closed.
Model/tool restrictions are repository policy, not the full CLI feature set.
These are structural checks, not proof of arbitrary skill composition,
instruction applicability, runtime behavior, or complete semantic consistency.
See [`scripts\README.md`](scripts/README.md) for exact scope and supported inputs.

Run the focused review-policy check and relevant isolated regression suites
separately when changing their corresponding surfaces:

```powershell
pwsh -NoProfile -File .\scripts\Validate-GitCommitReviewSkills.ps1
pwsh -NoProfile -File .\tests\ValidateConfig\Run-ValidateConfigTests.ps1
pwsh -NoProfile -File .\tests\Install\Run-InstallTests.ps1
pwsh -NoProfile -File .\tests\InstallProject\Run-InstallProjectTests.ps1
pwsh -NoProfile -File .\tests\Deploy\Run-DeployTests.ps1
pwsh -NoProfile -File .\tests\GitCommitReviewSkill\Run-GitCommitReviewSkillTests.ps1
pwsh -NoProfile -File .\tests\GitCommitReviewSkill\Run-GitSnapshotProcedureTests.ps1
```

Installer suites use disposable targets, not the active user installation.
The review-policy check verifies selected wording, not execution by an agent.
The snapshot-procedure suite executes the skill's marked example and shared
raw-tree helper in disposable repositories. It covers actual materialized bytes,
base/candidate contexts, validation integrity, ordered parents and destination
refs, restaged fixes, and inherited Git-state isolation.
Deployment regressions intercept target commands and use synthetic environment
values; they do not require a deployed host, private key, or active search service.
Compose structural checks use an isolated copy, an empty environment file and
`--no-interpolate`; they need no private deployment environment and do not
establish secret readiness, mount availability, or service readiness.

Commit-review evidence binds the tree, captured base, ordered parents,
unborn/detached/symbolic state, and destination ref. Before/after validation
guards invalidate observed tracked-input mutation; restoring old bytes later
cannot rescue that evidence. Validation entry points belong to the target
repository: merely containing Copilot instructions does not require this
repository's validator. The raw-tree helper rejects unsupported links,
submodules, LFS pointers and host-unrepresentable paths/modes instead of silently
transforming them. Its isolated command/pipe waits have no timeout guarantee;
isolation is not a sandbox or an atomic commit lock.

Enable the repository pre-commit hook to validate staged configuration changes
against an index-only snapshot:

```powershell
pwsh -NoProfile -File .\scripts\Enable-ConfigGitHook.ps1
```

The hook selects relevant additions, modifications, removals, and rename
sources/destinations, and fails when Git cannot enumerate the candidate.
Validation consumes a verified index-derived snapshot, not unstaged file
contents. The launcher, driver and helper themselves are worktree-resident; this
is a local development guard, not a tamper-proof boundary or a native Copilot hook.
The tracked launcher remains mode `100644`. Setup enables it per checkout on
POSIX without staging a mode change; a fresh POSIX checkout needs setup again
until an executable-mode commit is separately authorized. Windows fixture
results do not establish POSIX executable-mode fidelity, newline-filename
support, or fresh POSIX hook dispatch. Native Copilot lifecycle hooks remain deferred.

## MCP Servers

MCP (Model Context Protocol) integrations extend Copilot CLI with web search and browser automation. The remote Raspberry Pi stack runs pinned SearXNG; Playwright MCP runs locally on the workstation over stdio from the user-approved `@latest` package channel.

- **Quick start:** See [`mcps/README.md`](mcps/README.md)
- **Full reference:** See [`docs/mcps.md`](docs/mcps.md)
- **Deploy:** `.\mcps\deploy.ps1` (follow the runbook's private key, target, endpoint, and readiness setup first)

Provision a private source environment explicitly, then inspect the preview
before any authorized deployment:

```powershell
.\mcps\Initialize-Environment.ps1
.\mcps\deploy.ps1 -WhatIf
```

Provisioning is idempotent; key rotation requires explicit provisioning and
deployment rotation switches. Normal deployment recreates SearXNG to reload
settings; `-SkipCopy` validates retained inputs, and `-SkipCopy -Restart` requests
recreation explicitly. Remote mode transports through SSH stdin, not SCP.
The default `np-copilot-mcp` Compose project avoids orphan cleanup and never
automatically migrates or removes a legacy stack. Publication is not transactional.

The search bridge needs local Docker; Playwright needs Node.js/npm. Using both
integrations requires both prerequisites. SearXNG's HTTP JSON API is not an
HTTP/SSE MCP endpoint: the client launches a local stdio bridge. The bridge's
reachable URL must match the chosen deployment mode and published port, not
merely the server's advertised hostname.

## How It Works

### Configuration Precedence

| Level | Location | Scope |
|---|---|---|
| **Global** | Selected Copilot home | Shared defaults when installed and loaded from that home |
| **Project** | `.github/instructions/*.instructions.md` | Repo-specific: framework, build commands, feature toggles |
| **Local** | `.github/instructions/local-preferences.instructions.md` | Personal overrides, gitignored |

Copilot combines applicable guidance from every level. Follow the canonical
conflict-resolution policy in `instructions\coordination.instructions.md`:
project ownership, required evidence, approval, and delivery controls cannot be
waived by personal preferences, and higher-priority safety constraints remain.

### Operating Model

The global configuration governs **how** work is performed: verified atomic outcomes, proportionate workflow, user control, and repository-policy compliance.
Each repository defines **why** it exists—its mission, users, domain constraints, and delivery capabilities—in project-level instructions.

Cross-cutting policy has one canonical owner:

| Concern | Owner |
|---|---|
| Precedence, delegation, handoffs | `instructions/coordination.instructions.md` |
| Execution, proportional verification and stopping | `instructions/workflow.instructions.md` |
| Ownership, blockers, outcome verification, optional capabilities | `instructions/work-lifecycle.instructions.md` |
| Delivery path, protected branches, commit approvals | `instructions/git-conventions.instructions.md` |
| Session continuity | `instructions/session-awareness.instructions.md` |

Repositories opt into issue tracking, isolated worktrees, protected branches,
integration queues, and deployment evidence through one authoritative
`Agent Delivery Capabilities` declaration. Preserve an existing project-config
declaration; otherwise preserve the declaring root Copilot contract. The owner
and its references carry the same `np-copilot-capabilities-owner` marker, and
only the owner contains the table. Bootstrap and installer refreshes must not
introduce competing default-disabled values or reset verified capabilities.

The two supported owner identifiers are `.github/instructions/project-config.instructions.md`
and `.github/copilot-instructions.md`. Existing AGENTS/CLAUDE/GEMINI references
to either owner remain valid; independent declarations in those files require
an explicit preservation/reference or migration plan before generation.
Conflicting owners or references to missing declarations stop before mutation.
Absent or disabled optional capabilities add no process requirements.

### Symlinks

Copilot CLI reads configuration from the selected home. Rather than copying the
core definitions there, `install.ps1` symlinks them to this checkout.
Symlinks expose updated disk content; they do not prove that an active session
has reloaded it.

| Item | Symlink Source | Symlink Target |
|---|---|---|
| Root Instructions | `copilot-instructions.md` | `<CopilotHome>\copilot-instructions.md` |
| Instructions Folder | `instructions` | `<CopilotHome>\instructions` |
| Agents | `agents` | `<CopilotHome>\agents` |
| Skills | `skills` | `<CopilotHome>\skills` |
| MCP Config | `mcp-config.json` | `<CopilotHome>\mcp-config.json` *(opt-in link when absent, ownership-aware merge for an existing ordinary file)* |

Plugin-provided tools and skills are independent of these links. In particular,
an ignored `np-agent-memory` instruction imported from another home does not
install that plugin into the selected home. Preserve its external ownership,
verify availability before claiming persistence, and keep existing repository
artifacts truthful without creating duplicate unsolicited session handovers.

Shared snapshot procedures and bootstrap templates remain in the configuration
checkout; they are not copied into every downstream repository. Workflows must
resolve that source root and verify the required helper/assets explicitly.
A skill-directory-only copy is not self-contained unless a compatible, verified
source/asset root is also supplied; missing assets are not permission to invent
fallback procedures.

## Overriding Per-Repo

Repository-level config (`.github/copilot-instructions.md`, `.github/instructions/`, `.github/agents/`, `.github/skills/`) provides the more repository-specific guidance when combined instructions conflict. Use it when a project needs different behaviour.

This is the repository's instruction-conflict policy, not a guarantee of CLI
discovery precedence for same-named agents/skills. Check the effective definition
origin and resolved model for the actual CLI build and home; overrides, Auto,
and fallback can differ from the configured model. Personal preferences do not
override repository delivery or safety requirements.

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
