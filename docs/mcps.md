# MCP Integrations

The default architecture remains remote SearXNG on the Raspberry Pi, a local
Docker search bridge, and local Playwright over stdio. No remote browser-control
service or port is deployed.

```text
Copilot CLI (workstation)
  +-- local stdio --> SearXNG MCP bridge (workstation Docker container)
  |                    +-- HTTP JSON search --> SearXNG (default Pi:8080)
  |                    +-- direct URL retrieval --> requested web resources
  +-- local stdio --> Playwright MCP (npx, local browser)
```

SearXNG's HTTP JSON API is **not** an HTTP/SSE MCP endpoint. This repository
chooses the bridge's stdio mode; upstream bridge `v1.0.3` also implements an
optional HTTP transport. Its URL-reading tool can fetch directly from the
workstation container, rather than through the Pi.

## Versions and Dependencies

| Integration | Runtime location and prerequisites | Version policy |
|---|---|---|
| SearXNG | Selected deployment engine; Linux containers, Docker Engine + Compose v2 with JSON config/status support | `searxng/searxng:2026.8.22-9fea41204` |
| SearXNG MCP bridge | Workstation Docker CLI + running Linux-container engine; backend reachable from inside that container | `isokoliuk/mcp-searxng:1.0.3` |
| Playwright MCP | Workstation Node.js/npm (`npx`) meeting the selected package's engine requirement and supported local browser/runtime dependencies | `@playwright/mcp@latest`, **user-approved mutable-version waiver**, not a pin |

The combined client needs **both Docker and Node.js/npm**. The SearXNG
deployment host does not need Node.js for this stack. Remote deployment also
needs PowerShell 7+, an OpenSSH client and preconfigured trusted-key,
noninteractive access. Local deployment uses local Docker; WSL deployment
needs a usable distribution, `wslpath`, mounted source drive and an accessible
Docker engine. The [deployment runbook](../mcps/README.md) lists mode-specific
requirements; it does not install or configure them.

## Deployment and Endpoint Matrix

Three settings have different jobs: `-TargetHost` / `-DeployMode` selects
**where commands run**; private `.env` `SEARXNG_HOSTNAME` / `SEARXNG_PORT`
constructs the **advertised SearXNG base URL**; the client's `SEARXNG_URL`
selects the **HTTP address reachable from inside the bridge container**.
Changing one does not change the others.

| Mode / actual engine | Deployment arguments | Private `.env` hostname / host port | Advertised URL | Client bridge `SEARXNG_URL` |
|---|---|---|---|---|
| Default Remote Pi | `-TargetHost raspberrypi -User pi` | `raspberrypi` / `8080` | `http://raspberrypi:8080/` | `http://192.168.1.2:8080` (default Pi IP) |
| Remote, nondefault port | `-TargetHost 192.168.1.50 -User admin` | `192.168.1.50` / `9080` | `http://192.168.1.50:9080/` | `http://192.168.1.50:9080` |
| Local, Docker Desktop Linux engine | `-DeployMode Local` | `localhost` / `8080` | `http://localhost:8080/` | Normally `http://host.docker.internal:8080` with Docker Desktop host access |
| WSL CLI integrated with Docker Desktop | `-DeployMode WSL -WslDistro Ubuntu-24.04` | `localhost` / `9080` | `http://localhost:9080/` | Normally `http://host.docker.internal:9080`, **if the selected engine publishes there** |
| WSL distribution-native Docker engine | `-DeployMode WSL -WslDistro Ubuntu-24.04` | An address reachable by intended workstation users / `8080` | `http://<verified-distro-or-host-address>:8080/` | `http://<address-verified-from-bridge>:8080`; not automatically workstation or container `localhost` |

The last row is intentionally conditional: NAT/mirrored networking, distro
address changes, firewall rules and localhost forwarding vary. Verify the
actual route in an approved disposable environment instead of treating a
sample address as a deployment guarantee. Docker Desktop's
`host.docker.internal` is not a portable promise for every Linux/WSL engine.
On Linux Docker a deliberately configured host gateway/network route may be
needed; this repository does not install one.

**Container `localhost` refers to that container, not the workstation, Pi, or
another WSL distribution.** LAN hostnames may also fail inside a Docker
container even when they resolve on the workstation. The default IP avoids
that observed DNS dependency; it is not a claim that all hostnames fail.

For any custom port, edit `SEARXNG_PORT` in private `.env` and the matching
client URL. Only the **host** publication changes: container port and healthcheck
stay at **8080**. Compose explicitly maps `SEARXNG_SECRET` and the constructed
`SEARXNG_BASE_URL`, not the whole `.env`; forwarding `SEARXNG_PORT` into the
container would incorrectly override SearXNG's internal listener.

## Client Configuration

```powershell
.\install.ps1 -Mcp
```

The installer's selected home uses an absent-file **symlink** or an
existing-regular-file **merge with backup**. Existing user-owned server entries
win conflicts. Ownership/hashes let subsequent installs refresh unchanged owned
entries and preserve user modifications; removal/repair follows the installer's
ownership and recovery contract, not an unconditional whole-file overwrite.
A merged file is not live-linked. Editing through a symlink changes its source,
so choose deliberately where host-specific client customizations should live.

The shipped definition remains:

```json
{
  "mcpServers": {
    "searxng": {
      "type": "local",
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "SEARXNG_URL=http://192.168.1.2:8080",
        "isokoliuk/mcp-searxng:1.0.3"
      ]
    },
    "playwright": {
      "type": "local",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

Both entries launch local stdio processes without a TTY. Deployment neither
installs these entries nor adjusts their URLs; installer changes and active
session/process reload are separate operations.

## Private Configuration and Deployment

```powershell
.\mcps\Initialize-Environment.ps1
# Set hostname/host port in ignored mcps\.env using the matrix above.
.\mcps\deploy.ps1 -WhatIf
# When target actions are authorized:
.\mcps\deploy.ps1
```

The initializer creates a persistent, random 64-hex-character `SEARXNG_SECRET`
in private `.env`, never tracked YAML or console output. Valid keys survive
reruns. Explicit rotation uses `Initialize-Environment.ps1 -RotateSecret`
followed by `deploy.ps1 -RotateSecret`; a differing target key is otherwise a
preflight error. Compose requires the value, and deployment validates its
format and effective container mapping. The pinned SearXNG schema supports
`SEARXNG_SECRET`; this key is **not HTTP API authentication**.

Required Compose/settings sources are checked before target commands or writes.
With no source `.env`, normal deployment requires and preserves a valid private
target `.env` rather than claiming defaults. `-EnvPolicy Require` requires
source configuration. Explicit `-EnvPolicy Reset` restores example nonsecret
defaults while retaining an existing valid target key. `-SkipCopy` checks
deployed Compose/settings/private `.env` and effective Compose configuration;
it does not waive required inputs.

Normal deployment pulls the pinned image and deliberately **recreates**
SearXNG every time so settings-only changes are reloaded; expect a brief
interruption even with unchanged inputs. `-SkipCopy` reconciles without forced
restart; add `-Restart` to force recreation using the deployed files.
See the [full environment and restart contract](../mcps/README.md#reload-restart-and-environment-policy).

All Compose commands use explicit project `np-copilot-mcp` (or the chosen
`-ProjectName`); container/network names are project-scoped and no automatic
orphan removal runs. **Existing directory-derived/global-name stacks are not
migrated or deleted.** Plan migration/port ownership explicitly; changing the
project name alone does not stop the old stack.

## Network Trust Boundary and Recovery Limits

SearXNG publishes ordinary HTTP, without application authentication in this
configuration; its limiter is disabled. A port without a host bind address
normally publishes on all host interfaces, subject to Docker/OS/network rules.
This is a **trusted-network design**, not proof of Internet exposure or proof
of isolation. Establish intended reachability and access controls before live
use. Broader access requires a separately reviewed authentication/TLS/firewall
design; deployment does not configure those controls. SSH protects file
transfer, not later HTTP queries.

Search queries can leave the workstation for SearXNG and upstream engines.
Bridge URL retrieval uses the workstation container's network boundary.
Do not send secrets or private source as search/query text. Local browser
control remains local, but still requires deliberate tool-use authorization.
Host/Docker administrators can inspect container environment values; keep
`.env`, expanded Compose output, inspect output and raw logs private.

Deployment is **not an atomic publication/rollback transaction**. Sequential
copies and bind mounts can expose a partial input set before startup; failures
after copying, pulling, recreation or rotation can require manual recovery.
No success is reported on failure, and no automatic cleanup of old stacks is
attempted. A timed-out SSH client does not prove its remote command stopped.
Privately inspect the selected project, preserve the necessary recovery
material, restore coherent known-good inputs if appropriate, and rerun the
intended operation under its authorization. `-SkipCopy` is not rollback.

## Verification and Troubleshooting

The deployment command waits for exactly one running, healthy SearXNG service,
bounded by `-ReadinessTimeoutSeconds` (default 180). Missing/unhealthy/exited
services, invalid health evidence, native failures and timeouts fail without
a ready banner. `-WhatIf` issues no target commands and explicitly leaves
deployed inputs/effective key/readiness unverified.

Health establishes only the configured container `/healthz` check, not external
reachability, valid JSON search behavior, or a successful MCP handshake. After
separate approval, an example public-query smoke check is:

```powershell
$base = 'http://192.168.1.2:8080' # Choose the endpoint reachable by this caller.
$response = Invoke-RestMethod -Uri "$base/search?q=searxng&format=json" -TimeoutSec 15
if ($null -eq $response -or -not $response.PSObject.Properties['results'] -or
    $response.results -isnot [array]) {
    throw 'Search did not return the expected JSON results array.'
}
# Empty results are valid; they are not, by themselves, a transport failure.
```

That workstation request does not prove the bridge container can reach the
same address. A separate, approved client-side check must exercise that route.

| Symptom | Check / action |
|---|---|
| Missing/invalid key or differing source/target key | Initialize privately; preserve an existing valid key or authorize rotation explicitly. Do not paste values into diagnostics. |
| First isolated-project start cannot bind its port | Inspect legacy-stack/port ownership; do not automatically delete old containers/networks. |
| Health succeeds but no search tools / connection fails | Check the selected client entry, container-reachable URL, engine/network boundary and active MCP process. |
| Valid JSON has no results | Engines can be blocked/rate-limited; empty results alone are not proof of a broken transport. |
| Settings appear unchanged | Normal deployment recreates; `-SkipCopy` alone does not. Confirm the intended target/project and settings before explicit recreation. |
| No Playwright tools | Check local Node/npm, browser dependencies and the user-waived mutable package, not a nonexistent remote browser service. |
| MCP entry conflict | Preserve user-owned edits; resolve deliberately through the installer's ownership/repair contract. |

Run isolated regression checks without a deployed host:

```powershell
pwsh -NoProfile -File .\tests\Deploy\Run-DeployTests.ps1
```

The suite uses intercepted commands and disposable nonsecret fixtures; available
Compose parsing is read-only. Repository-wide structural validation remains
`pwsh -NoProfile -File .\scripts\Validate-Config.ps1`; any Compose validation
must use an isolated nonsecret environment, never a production `.env` or a
real key in printed output.

## Adding an Integration

Choose an explicit transport/runtime boundary: a backend plus local bridge,
local stdio MCP, or an authenticated network MCP endpoint when remote access
is necessary. Do not silently enable multiple transports. New images/packages
need explicit versions, applicable structural checks and an ownership-safe
installer lifecycle. The Playwright waiver remains narrow; Context7 remains
[deferred](features/context7-mcp.md).
