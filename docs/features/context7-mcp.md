# Feature: Context7 MCP Integration

## Status: Under Consideration

## What

[Context7](https://github.com/upstash/context7) by Upstash is an MCP server that provides real-time, version-specific library documentation and code examples directly to AI assistants.

## Why

- .NET, Angular, and EF Core APIs evolve frequently — training data goes stale
- Avoids hallucinated APIs by grounding responses in actual current documentation
- Covers 33,000+ public libraries

## How It Works

- Runs as a stdio subprocess (local via npx) or connects to a remote HTTP endpoint
- When invoked (e.g., `use context7` in a prompt), fetches live docs for the specified library/version
- No source code leaves your machine — only library name/version queries go to Context7's cloud API

## Configuration Options

### Remote (simplest, no local deps)

```json
{
  "context7": {
    "url": "https://mcp.context7.com/mcp"
  }
}
```

### Local stdio (requires Node.js ≥ 18)

```json
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp@latest"]
  }
}
```

## Pricing

- Free tier available (rate-limited, no key required)
- API key (free from context7.com/dashboard) for higher limits
- Paid plans for enterprise/heavy usage

## Security Assessment

| Aspect | Notes |
|--------|-------|
| Provider | Upstash — SOC 2 Type II certified |
| Trust score | 86/100 (MCP Scorecard) |
| Past vulnerabilities | ContextCrush disclosed and patched promptly |
| Data sent | Library name + version queries only (no source code) |
| Self-hostable | No — docs database is cloud-hosted by Upstash |

## Open Questions

- [ ] Verify .NET / EF Core / Angular coverage quality with manual testing
- [ ] Check rate limits on free tier for typical daily usage
- [ ] Evaluate whether Copilot's built-in knowledge is sufficient for our stack without Context7
- [ ] Confirm no corporate policy conflicts with sending queries to Upstash

## Decision

Deferred — pending manual research and evaluation.
