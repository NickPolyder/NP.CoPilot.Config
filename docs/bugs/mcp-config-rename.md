# Bug Fix: MCP Config File Naming and Server Connectivity

## Problem

Three issues prevented MCP servers from working with Copilot CLI:

1. **Wrong filename** — Copilot CLI reads `~/.copilot/mcp-config.json`, but the repo had `mcp.json`.
2. **Playwright access denied** — Playwright MCP rejected remote connections with "Access is only allowed at localhost:8931".
3. **SearXNG 403 Forbidden** — SearXNG blocked JSON API requests, and the bridge container couldn't resolve the Pi's hostname.

## Root Causes

1. The filename was based on an earlier assumption. Official docs confirm `mcp-config.json`.
2. Playwright MCP requires `--allowed-hosts *` to accept non-localhost clients. The `--allowed-origins` flag controls browser navigation origins, not client access.
3. SearXNG defaults to HTML-only output; JSON format must be explicitly enabled via `search.formats`. The Docker bridge container also couldn't resolve `raspberrypi` — switched to IP.

## Fix

### 1. Renamed `mcp.json` → `mcp-config.json`

Updated all references in:
- `install.ps1` (link definition + help text)
- `README.md` (structure tree + symlinks table)
- `docs/mcps.md` (config section + troubleshooting)
- `mcps/README.md` (connect section)

### 2. Added merge support to `install.ps1`

When `-Mcp` is specified and a regular file (not a symlink) already exists at `~/.copilot/mcp-config.json` (e.g. created by `/mcp add`):

1. Parses both JSON files
2. Merges `mcpServers` at the server-name level — **existing target entries win** on conflict
3. Preserves all non-`mcpServers` properties from the target
4. Backs up the original before writing
5. Prints a detailed summary of what was added vs kept
6. Warns that the merged file is no longer a live symlink

Uninstall detects merged files and warns the user to delete manually.

### 3. Fixed Playwright remote access

Added `command` to `docker-compose.yml` for the `playwright-mcp` service:

```yaml
command: ["--port", "8931", "--host", "0.0.0.0", "--allowed-hosts", "*"]
```

### 4. Fixed SearXNG JSON API and DNS

- Added `formats: [html, json]` to `mcps/searxng/settings.yml` to enable the JSON search API.
- Changed `mcp-config.json` to use the Pi's IP (`192.168.1.2`) instead of hostname, since the Docker bridge container on the workstation can't resolve LAN hostnames.

## Future Improvements

- Could add a `-ForceMerge` flag to re-merge even when a symlink exists
- Could track merge state to allow "unmerge" (restore backup + symlink)
- Consider making the Pi IP configurable via an environment variable in `mcp-config.json`
