# Self-Hosted MCP Servers

Model Context Protocol (MCP) servers extend GitHub Copilot CLI with additional capabilities by exposing external tools over a standardised protocol. This document covers the self-hosted MCP servers running on a local Raspberry Pi.

## Overview

The MCP stack provides two capabilities to Copilot CLI:

1. **Web search** — Privacy-respecting search via SearXNG, exposed as an MCP tool through a local bridge process.
2. **Browser automation** — Headless Chromium via Playwright, exposed as an MCP tool for page interaction, screenshots, and scraping.

### Architecture

```
Copilot CLI (your workstation)
  ├── searxng MCP bridge (stdio, runs locally via npx/docker)
  │     └── queries → SearXNG HTTP API (on Pi, port 8080)
  └── playwright MCP (SSE, network) ──→ Playwright container (on Pi, port 8931)
```

**Why the split?** The SearXNG MCP bridge (`isokoliuk/mcp-searxng`) is a **stdio-only** MCP server — it communicates over stdin/stdout and has no built-in HTTP/SSE transport. It must be launched by the MCP client as a subprocess. Playwright MCP supports `--port` for SSE transport and runs as a persistent network service.

The Docker Compose stack on the Pi runs **SearXNG** (the search engine) and **Playwright MCP** (the browser). The SearXNG MCP bridge runs locally on your workstation, launched by Copilot CLI, and reaches SearXNG over the network.

## Server Reference

| Component | Image | Runs On | Transport | Port |
|---|---|---|---|---|
| SearXNG | `searxng/searxng:latest` | Pi (Docker) | HTTP API | 8080 |
| SearXNG MCP Bridge | `isokoliuk/mcp-searxng:latest` | Workstation (stdio) | stdio | — |
| Playwright MCP | `mcp/playwright:latest` | Pi (Docker) | SSE (HTTP) | 8931 |

### SearXNG

SearXNG is a self-hosted metasearch engine that aggregates results from multiple search providers (Google, DuckDuckGo, Bing, Wikipedia, GitHub) without tracking. It runs as a standalone HTTP service that the MCP bridge queries.

- **Memory limit:** 512 MB
- **Configuration:** [`mcps/searxng/settings.yml`](../mcps/searxng/settings.yml)
- **Why self-hosted:** No API keys required, no rate limits from third-party search APIs, full control over which engines are queried.

### SearXNG MCP Bridge

A lightweight Node.js process that connects to SearXNG's HTTP API and exposes search as an MCP-compatible tool. Copilot CLI launches this as a subprocess — it does **not** run on the Pi.

- **Transport:** stdio only (no HTTP/SSE server mode)
- **Environment variable:** `SEARXNG_URL` must point to the SearXNG instance on the Pi.
- **Install options:** `npx mcp-searxng` or `docker run -i --rm isokoliuk/mcp-searxng`

### Playwright MCP

Provides headless Chromium browser automation as an MCP tool. Useful for interacting with web pages, taking screenshots, extracting content from JavaScript-rendered sites, and filling forms.

- **Memory limit:** 1 GB
- **Shared memory:** 512 MB (`/dev/shm` — required by Chromium)
- **Runs headless:** Configured via `PLAYWRIGHT_MCP_HEADLESS=true` environment variable.
- **SSE transport:** Configured via `PLAYWRIGHT_MCP_PORT` and `PLAYWRIGHT_MCP_HOST=0.0.0.0` environment variables.

## Connecting Copilot CLI

### MCP Configuration

The repo includes a ready-to-use [`mcp-config.json`](../mcp-config.json) at the repo root. Install it into `~/.copilot/` using the install script:

```powershell
.\install.ps1 -Mcp
```

This uses the Docker-based SearXNG bridge with a **pinned version** for supply-chain safety. The config:

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

> **Note:** Replace the IP with the address of the machine running the Docker stack. The SearXNG bridge uses the IP directly because it runs inside a Docker container on your workstation where the hostname may not resolve. Playwright connects directly from the host OS, so hostname resolution works. The Playwright endpoint uses `/mcp` (streamable HTTP); `/sse` is also supported as a legacy fallback.

#### Alternative: npx-based SearXNG bridge

If you prefer `npx` over Docker for the local bridge:

```json
"searxng": {
  "type": "local",
  "command": "npx",
  "args": ["-y", "mcp-searxng"],
  "env": {
    "SEARXNG_URL": "http://raspberrypi:8080"
  }
}
```

> **⚠️ Supply chain risk:** `npx -y` always fetches the latest version. Consider pinning: `"args": ["-y", "mcp-searxng@1.0.3"]`

### Verifying the Connection

Once configured, Copilot CLI should list the MCP tools when it starts a session. You can verify with:

- `/env` — shows loaded MCP servers and their tools
- Ask Copilot to perform a web search or browse a page

## Docker Compose Stack

The stack on the Pi is defined in [`mcps/docker-compose.yml`](../mcps/docker-compose.yml). Key design decisions:

- **Dedicated network** (`mcp-network`) — Containers communicate internally.
- **Health checks** — SearXNG has a health check for readiness verification.
- **Restart policy** — All containers use `unless-stopped` so they survive reboots.
- **Resource limits** — Memory caps prevent runaway containers from exhausting the Pi's limited RAM.
- **Environment-based config** — Playwright MCP uses environment variables (`PLAYWRIGHT_MCP_PORT`, `PLAYWRIGHT_MCP_HOST`, `PLAYWRIGHT_MCP_HEADLESS`) instead of command-line args for cleaner compose files.

### Published Ports

| Port | Service | Exposed To |
|---|---|---|
| 8080 | SearXNG HTTP API + web UI | LAN (bridge queries this; also useful for debugging) |
| 8931 | Playwright MCP (SSE) | LAN (Copilot CLI connects here) |

## Adding a New MCP Server

MCP servers come in two flavours — choose the right pattern:

### Network MCP (SSE transport — like Playwright)

The server runs as a persistent container on the Pi with an HTTP/SSE endpoint.

1. **Add the service** to `mcps/docker-compose.yml`:

   ```yaml
   new-mcp-server:
     image: your/image:tag
     container_name: new-mcp-server
     restart: unless-stopped
     ports:
       - "${NEW_MCP_PORT:-9000}:9000"
     networks:
       - mcp-network
     deploy:
       resources:
         limits:
           memory: 256m
   ```

2. **Add the MCP config** entry:

   ```json
   {
     "new-mcp-server": {
       "url": "http://raspberrypi:9000/mcp"
     }
   }
   ```

### Stdio MCP (subprocess — like SearXNG bridge)

The server is launched by Copilot CLI as a local subprocess.

1. **Add the MCP config** entry:

   ```json
   {
     "new-mcp-server": {
       "type": "local",
       "command": "npx",
       "args": ["-y", "new-mcp-package"],
       "env": {
         "SOME_URL": "http://raspberrypi:9000"
       }
     }
   }
   ```

2. If the stdio MCP needs a backend service on the Pi, add that service to `docker-compose.yml`.

### Common steps

3. **Add environment variables** to `mcps/.env.example` and your deployed `.env`.
4. **Deploy** with `mcps/deploy.ps1`.
5. **Document** the new server in this file.

## Deployment

See [`mcps/README.md`](../mcps/README.md) for deployment instructions and the deploy script reference.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Copilot can't find MCP tools | MCP config not loaded or wrong URL | Run `/env` to check. Verify `mcp-config.json` and that containers are running |
| Search returns no results | SearXNG engines blocked or rate-limited | Check SearXNG web UI at `:8080`, try different engines |
| Playwright times out | Container OOM or Chromium crash | Check `docker logs playwright-mcp`, increase memory limit |
| Playwright exits with code 0 | Missing `--port` / env vars | Ensure `PLAYWRIGHT_MCP_PORT` and `PLAYWRIGHT_MCP_HOST=0.0.0.0` are set |
| SearXNG MCP bridge restart loop | Running as Docker service (stdio-only) | Don't run in compose — launch via MCP client config instead |
| `chown: Read-only file system` on SearXNG | settings.yml mounted as `:ro` | Harmless warning — SearXNG starts fine, the entrypoint just can't chown |
| Memory limit warnings on Pi | Kernel cgroup config | Enable memory cgroup: add `cgroup_memory=1 cgroup_enable=memory` to `/boot/cmdline.txt` and reboot |
