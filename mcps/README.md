# MCP Server Stack

Self-hosted Model Context Protocol (MCP) servers that extend Copilot CLI with web search and browser automation.

For full documentation, see [docs/mcps.md](../docs/mcps.md).

## Quick Start

### Prerequisites

- A Linux host with Docker and Docker Compose installed (tested on Raspberry Pi OS)
- SSH access from your workstation to the target host
- PowerShell 7+ on your workstation (for the deploy script)
- Node.js 18+ **or** Docker on your workstation (for the SearXNG MCP bridge)

### 1. Configure

```powershell
Copy-Item mcps/.env.example mcps/.env
# Edit mcps/.env with your host details
```

Update `mcps/searxng/settings.yml` — at minimum, change `secret_key` to a random value:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 2. Deploy

Deploy to a **remote host** (default — Raspberry Pi):

```powershell
.\mcps\deploy.ps1
.\mcps\deploy.ps1 -TargetHost 192.168.1.50 -User admin
```

Deploy to **this machine** (Docker Desktop on Windows):

```powershell
.\mcps\deploy.ps1 -DeployMode Local
.\mcps\deploy.ps1 -DeployMode Local -RemotePath C:\DockerScripts
```

Deploy to **WSL**:

```powershell
.\mcps\deploy.ps1 -DeployMode WSL
.\mcps\deploy.ps1 -DeployMode WSL -WslDistro Ubuntu-24.04
```

Preview what would happen without deploying:

```powershell
.\mcps\deploy.ps1 -WhatIf
```

### 3. Connect Copilot CLI

From the repo root, run the install script with `-Mcp` to symlink the MCP config:

```powershell
.\install.ps1 -Mcp
```

This installs [`mcp-config.json`](../mcp-config.json) into `~/.copilot/mcp-config.json`. If an existing `mcp-config.json` is found (e.g. from `/mcp add`), it merges server entries; otherwise it creates a symlink. Edit `mcp-config.json` if your host isn't `raspberrypi`:

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
      "url": "http://raspberrypi:8931/mcp"
    }
  }
}
```

Replace the IP (`192.168.1.2`) with your Pi's address. The SearXNG bridge uses the IP directly because the hostname won't resolve inside the Docker container on Windows.

> **Note:** The SearXNG MCP bridge runs locally on your workstation (stdio transport) — it queries SearXNG on the Pi over HTTP. Playwright MCP runs on the Pi and Copilot connects to it directly over the network.

## File Layout

```
mcps/
├── docker-compose.yml       # Docker Compose stack (SearXNG + Playwright)
├── searxng/
│   └── settings.yml         # SearXNG engine and server configuration
├── .env.example             # Environment variable template
├── deploy.ps1               # Deployment script (SCP + docker compose)
└── README.md                # This file
```

## Services on Host

| Service | Port | Description |
|---|---|---|
| SearXNG | 8080 | Metasearch engine (HTTP API + web UI for debugging) |
| Playwright MCP | 8931 | Headless browser MCP tool (SSE transport) |

## Local MCP Bridge

| Service | Transport | Description |
|---|---|---|
| SearXNG MCP Bridge | stdio | Launched by Copilot CLI, queries SearXNG over HTTP |

## Updating

To pull latest images and restart:

```powershell
.\mcps\deploy.ps1
```

The deploy script always pulls latest images before starting containers.

## Manual Operations

SSH into the Pi and manage directly:

```bash
cd ~/DockerScripts
docker compose -f mcps.docker-compose.yml logs -f            # Follow logs
docker compose -f mcps.docker-compose.yml restart searxng     # Restart one service
docker compose -f mcps.docker-compose.yml down                # Stop everything
```
