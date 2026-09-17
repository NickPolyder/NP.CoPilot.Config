# MCP Server Stack

SearXNG is the only deployed service. The search MCP bridge and Playwright MCP
are **local stdio processes** on the workstation. See [MCP integrations](../docs/mcps.md)
for the endpoint matrix, trust boundary, installer lifecycle and recovery limits.

## Prerequisites

| Integration / operation | Workstation | Deployment target |
|---|---|---|
| SearXNG MCP bridge (`isokoliuk/mcp-searxng:1.0.3`) | Docker CLI and running Linux-container engine | Reachable SearXNG HTTP endpoint |
| Playwright MCP (`@playwright/mcp@latest`) | Node.js/npm (`npx`) meeting the package's current engine requirement, plus supported local browser dependencies | None; no remote browser port |
| Remote deployment | PowerShell 7+, OpenSSH client, preconfigured noninteractive SSH authentication and trusted host key | Linux, POSIX `sh`, standard file utilities, Docker Engine + Compose v2 with JSON config/status support |
| Local deployment | PowerShell 7+, Docker CLI + Compose v2; on Windows, Docker Desktop with Linux containers | This machine's selected Docker engine |
| WSL deployment | PowerShell 7+, WSL (`wsl.exe`), selected/default distribution | `sh`, `wslpath`, file utilities, Docker CLI + Compose v2 and an accessible engine; source drive mounted in WSL |

The **combined shipped client requires both Docker and Node.js/npm**, not either
one. Deployment does not install dependencies, launch Docker/WSL infrastructure,
configure SSH, or change the MCP client endpoint.

## Configure Privately

```powershell
.\mcps\Initialize-Environment.ps1
# Edit the ignored mcps\.env: SEARXNG_HOSTNAME and SEARXNG_PORT.
# Keep the generated SEARXNG_SECRET private. Do not edit a key into settings.yml.
```

The initializer generates a 32-byte random key once, writes 64 hexadecimal
characters to `.env`, and restricts file access (current-user ACL on Windows,
mode `600` on POSIX). Reruns preserve a valid key and existing configuration.
Missing/placeholder/repeated-character keys are rejected by deployment.
Format validation cannot prove entropy; use the initializer rather than a
hand-chosen key. `.env.example` deliberately cannot deploy as-is.

Private `.env` uses single-line literal assignments; the three supported
`SEARXNG_*` inputs may be unquoted or simply quoted. Duplicate assignments,
interpolation/escape expressions in those values, invalid ports, and malformed
input fail explicitly. Other single-line assignments are retained but are not
automatically forwarded into the SearXNG container.

## Deploy

```powershell
# Preview only: no target commands, file publication, key generation or readiness claim.
.\mcps\deploy.ps1 -WhatIf

# Default Pi: pi@raspberrypi, ~/DockerScripts, project np-copilot-mcp.
.\mcps\deploy.ps1
.\mcps\deploy.ps1 -TargetHost 192.168.1.50 -User admin

# Docker Desktop: also adjust .env and the client's SEARXNG_URL as documented.
.\mcps\deploy.ps1 -DeployMode Local -RemotePath 'C:\DockerScripts\Search stack'

# Selected or default WSL distribution.
.\mcps\deploy.ps1 -DeployMode WSL -WslDistro Ubuntu-24.04
.\mcps\deploy.ps1 -DeployMode WSL

# Custom target filename and punctuation are literal arguments.
.\mcps\deploy.ps1 -RemotePath "~/DockerScripts/O'Brien search" -ComposeFile 'search stack.yml'
```

Remote/WSL destinations must be absolute or start with `~/`; `~otheruser` and
shell expressions are not expanded. `-ComposeFile` is a target filename, not
an alternate source. Remote transfers use SSH stdin, not an SCP command string.
WSL source paths are converted by `wslpath` **inside WSL**, never in host PowerShell.
Local mode assumes a native Docker CLI that accepts Windows paths on Windows.
A wrapper that reparses Windows arguments in a Linux shell is not equivalent to
Docker Desktop; validate that wrapper separately or use the explicitly selected
WSL mode when its target is approved. Offline Compose parsing alone cannot
establish that a workstation's wrapper supports Local deployment.

**Migration warning:** the explicit project `np-copilot-mcp` and project-scoped
container/network names replace the old directory-derived project, global
`searxng` container and `mcp-network` network. The script does not adopt/delete
old stacks or use `--remove-orphans`. An old stack can still own port 8080.
Inspect ownership and plan any stop/migration separately before first use.
For another independent stack, choose a distinct `-ProjectName`, directory and
published port; reuse that identity in every manual Compose command.

## Reload, Restart and Environment Policy

| Operation | Behavior |
|---|---|
| Normal deployment, even unchanged inputs | Preflight source files, publish, validate effective Compose, pull the pinned image, `up -d --no-deps --force-recreate searxng`, wait for health |
| `-SkipCopy` | Require/validate deployed Compose, settings and private `.env`; pull and reconcile with `up`, without forced restart |
| `-SkipCopy -Restart` | As above, but force recreation to reload deployed settings/environment |
| Default `-EnvPolicy Preserve`, source `.env` present | Copy validated source config; reject a different deployed key unless `-RotateSecret` is explicit |
| Default `-EnvPolicy Preserve`, source `.env` absent | Require a valid private target `.env`, retain its bytes/settings/key, and report preservation, not defaults |
| `-EnvPolicy Require` | Require source `.env` before any target commands |
| `-EnvPolicy Reset` | Ignore source `.env` for this run; replace nonsecret settings with `.env.example` defaults while preserving a valid target key |

`Require`, `Reset`, and `-RotateSecret` cannot be combined with `-SkipCopy`.
`Reset` cannot initialize a missing target key or rotate it. A later normal
deployment with a source `.env` will apply that source again.

Normal recreation is deliberate: SearXNG reads settings at initialization and
Compose does not necessarily notice bind-mounted file-content changes. The
tradeoff is a brief interruption on every normal deployment. `-SkipCopy` is not
a synonym for restart, nor a bypass for missing or invalid inputs.

To rotate an existing key, explicitly authorize **both** local provisioning and
publication; store any needed old configuration in a private recovery location:

```powershell
.\mcps\Initialize-Environment.ps1 -RotateSecret
.\mcps\deploy.ps1 -RotateSecret
```

Deployment never generates keys implicitly. A target's legacy/invalid key can
only be replaced using a valid source `.env` and explicit `-RotateSecret`.
Rotation can invalidate existing SearXNG session/preferences state.

## Readiness and Failures

Success requires exactly one running, healthy SearXNG service. Missing,
unhealthy, exited/stopped, malformed or absent health evidence fails; a service
that stays `starting` fails after `-ReadinessTimeoutSeconds` (default 180).
Status commands share that deadline. Other native commands each have
`-CommandTimeoutSeconds` (default 300); SSH connection establishment is also bounded.
Native failures stop subsequent phases and preserve their exit code.

`-WhatIf` performs applicable source checks but does not contact a target. A
missing local `.env` can therefore be previewed, but the preview explicitly
leaves the deployed key/configuration/readiness unverified. Health is not
functional JSON-search or MCP-handshake evidence.

Publication is **not an atomic stack transaction**: files are copied
sequentially, and bind-mounted settings can change before recreation. A later
failure can leave mixed inputs, old/new containers, or a pending explicit
rotation. There is no automatic rollback. A transport timeout does not prove
the remote process stopped. Recover by privately inspecting the selected
project and its deployed inputs, restoring a coherent known-good set if needed,
and rerunning the intended deployment. Do not use broad `down`/orphan deletion
as recovery, or assume `-SkipCopy` repairs a partial publication.

## Connect the Client

```powershell
.\install.ps1 -Mcp
```

In the installer's selected Copilot home, an absent `mcp-config.json` becomes
a symlink; an existing regular file is merged with a backup, preserving
user-owned entries on conflict. A merged file is not a live symlink. Ownership
records govern later updates/removal; see [the client lifecycle](../docs/mcps.md#client-configuration).

The tracked default bridge URL remains `http://192.168.1.2:8080`; deployment
does not rewrite it. Docker-container `localhost` is **not** the workstation.
Use the [per-mode endpoint matrix](../docs/mcps.md#deployment-and-endpoint-matrix)
before switching modes, hosts or ports. Playwright retains its user-approved
mutable `@latest` waiver; it is not pinned.

## Manual Operations

Only after separately authorizing access to the intended host/project:

```bash
cd ~/DockerScripts
docker compose --project-name np-copilot-mcp --env-file .env -f mcps.docker-compose.yml logs --tail 100 searxng
docker compose --project-name np-copilot-mcp --env-file .env -f mcps.docker-compose.yml ps --all
```

Keep inherited `SEARXNG_*`/`COMPOSE_*` overrides out of manual commands; unlike
the script, a plain shell command may override `.env`. Do not publish raw logs,
`.env`, expanded `compose config`, or `docker inspect` output: they can contain
private values. Docker/host administrators can read runtime environment values.

## Local Regression Checks

```powershell
pwsh -NoProfile -File .\tests\Deploy\Run-DeployTests.ps1
```

The dependency-free Windows PowerShell suite intercepts deployment commands,
uses only owned temporary fixtures, and never starts SSH/WSL/Docker services.
When available, Git Bash exercises quoting/copy scripts locally and Compose
performs read-only parsing with a controlled nonsecret key. These checks do
not prove live transfer, image compatibility, network access or search behavior.
