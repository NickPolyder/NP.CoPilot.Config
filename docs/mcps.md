# MCP Integrations

MCP integrations extend Copilot CLI with web search and browser automation.
The selected architecture intentionally separates remote search infrastructure from local browser control:

- **SearXNG** runs as a pinned Docker service on the Raspberry Pi.
- The **SearXNG MCP bridge** runs locally over stdio and queries SearXNG over HTTP.
- **Playwright MCP** runs locally over stdio from npm's `@latest` package
  channel, by user-approved exception.

No remote browser-control service or port is deployed.

## Architecture

```text
Copilot CLI (workstation)
  ├── SearXNG MCP bridge (local stdio Docker process)
  │     └── queries -> SearXNG (Pi, HTTP port 8080)
  └── Playwright MCP (local stdio npx process)
        └── controls a local browser
```

This removes the former unauthenticated LAN browser-control endpoint while retaining browser automation for the local Copilot session.

## Versions

| Component | Location | Pinned version |
|---|---|---|
| SearXNG | Raspberry Pi Docker Compose | `searxng/searxng:2026.8.22-9fea41204` |
| SearXNG MCP bridge | Workstation Docker subprocess | `isokoliuk/mcp-searxng:1.0.3` |
| Playwright MCP | Workstation npx subprocess | `@playwright/mcp@latest` (user-approved mutable-version waiver) |

SearXNG and the SearXNG bridge use explicit versions. Playwright intentionally
follows `@latest` at the user's direction; the validator reports that narrow
exception as a warning and continues to reject other mutable runtime versions.

## Client Configuration

Install the repository-owned MCP entries:

```powershell
.\install.ps1 -Mcp
```

The installer either creates an `mcp-config.json` symlink or merges repository-owned entries into an existing user config.
Its manifest records ownership and hashes so later installs can update unchanged owned entries, preserve user entries, and report conflicts without printing values or secrets.

Check the active state without exposing endpoints or configuration bodies:

```powershell
.\install.ps1 -Status
```

Repair only missing or drifted repository-owned artifacts:

```powershell
.\install.ps1 -Repair
```

The tracked client definition is:

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
      "args": [
        "-y",
        "@playwright/mcp@latest"
      ]
    }
  }
}
```

Replace the SearXNG IP with the address of the deployed host.
The bridge uses an IP because it runs inside Docker, where the LAN hostname may not resolve.

## Remote SearXNG Deployment

The remote stack is defined by `mcps\docker-compose.yml`.
It contains only SearXNG and publishes only the SearXNG HTTP port.

```powershell
Copy-Item mcps\.env.example mcps\.env
.\mcps\deploy.ps1
```

Use the deploy script's `-WhatIf` option to preview target changes.
The service image is pinned; deployment pulls that exact tag rather than a mutable `latest` tag.

## Validation and Troubleshooting

Run the structural checks after changing MCP files:

```powershell
pwsh -NoProfile -File .\scripts\Validate-Config.ps1
```

| Symptom | Likely cause | Action |
|---|---|---|
| No SearXNG tools | Client entry is absent or remote service is unavailable | Run `.\install.ps1 -Status`, then check the SearXNG service. |
| Search returns no results | SearXNG engines are blocked or rate-limited | Check the SearXNG web UI on port 8080 and try another engine. |
| No Playwright tools | Node/npm cannot launch the local pinned package | Verify Node.js is installed and restart Copilot CLI. |
| Browser automation fails | Local browser dependency or package issue | Review the local Playwright MCP process output; do not open a remote browser-control port as a workaround. |
| MCP entry conflict | A repository-owned entry was edited locally | Preserve the local change or resolve it deliberately, then run `.\install.ps1 -Repair`. |

## Adding an Integration

Choose one explicit model:

- **Remote service plus local stdio bridge:** Use a pinned remote backend only when a local bridge needs it, as with SearXNG.
- **Local stdio MCP:** Prefer this for workstation-only capability such as browser automation.
- **Remote network MCP:** Use only when remote access is necessary and the service has an explicit authentication and network-boundary design.

Do not ship both local and remote transports for the same integration without a documented decision.
All new runtime images and packages must use explicit versions, be covered by `Validate-Config.ps1`, and have a safe installer lifecycle.
