# Feature: Context7 MCP Integration

## Status: Deferred

Documentation assessment only; no Context7 entry, package, service, API key or
network integration is installed or approved by this document.

## What

[Context7](https://github.com/upstash/context7) by Upstash is an MCP server that provides real-time, version-specific library documentation and code examples directly to AI assistants.

## Why

- .NET, Angular, and EF Core APIs evolve frequently — training data goes stale
- Avoids hallucinated APIs by grounding responses in actual current documentation
- Covers 33,000+ public libraries

## How It Works

- Runs as a stdio subprocess (local via npx) or connects to a remote HTTP endpoint
- When invoked (e.g., `use context7` in a prompt), fetches live docs for the specified library/version
- Both transports can send **free-form query text** to Context7's cloud API,
  not just library names/versions. Running the MCP process locally does not
  make its documentation lookup offline or automatically exclude private code.

### Reviewed Payload Model

Reviewed on **2026-09-16** at upstream commit
[`4416fb855b8f752be735e34f943b5d0762701aad`](https://github.com/upstash/context7/tree/4416fb855b8f752be735e34f943b5d0762701aad);
the [package manifest](https://github.com/upstash/context7/blob/4416fb855b8f752be735e34f943b5d0762701aad/packages/mcp/package.json)
declares `@upstash/context7-mcp` **4.1.1**. This is a source-review reference,
not an installed-version claim or an approval to adopt it.

The reviewed [tool definitions](https://github.com/upstash/context7/blob/4416fb855b8f752be735e34f943b5d0762701aad/packages/mcp/src/index.ts)
accept `query` with `libraryName` for library resolution, and `query` with
`libraryId` for documentation lookup. Both query descriptions explicitly warn
against confidential information, credentials, personal data and proprietary
code. The [API implementation](https://github.com/upstash/context7/blob/4416fb855b8f752be735e34f943b5d0762701aad/packages/mcp/src/lib/api.ts)
sends those strings as URL query parameters to `/v2/libs/search` and
`/v2/context`, respectively; a library ID can include a version.
Authentication/client metadata can also accompany requests. This limited
payload review is not a complete telemetry, retention or privacy audit.

## Candidate Configuration Options (Not Enabled)

Examples describe possible future transport choices, not commands to apply.
Adoption, package/runtime selection, credentials and network access require
separate approval and a refreshed review.

### Remote (simplest, no local deps)

```json
{
  "context7": {
    "url": "https://mcp.context7.com/mcp"
  }
}
```

### Local stdio

The reviewed 4.1.1 manifest requires Node.js `>=20.18.1`. Reverify that
requirement and an explicit package version before adoption; there is no
Context7 mutable-version waiver.

```json
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp@4.1.1"]
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
| Data sent | Free-form query plus library name/ID (possibly versioned), with applicable request metadata; confidential text/code can leave if placed in arguments |
| Self-hostable | No — docs database is cloud-hosted by Upstash |

The provider/score/vulnerability and pricing notes above are historical
evaluation leads, not newly verified assurances or adoption criteria.

### Data Minimization and Approval

Before any future use, approve the provider, transport, credential handling and
permitted data classes under the consuming repository/organization policy.
Review the **actual tool arguments**, not merely the requested library name.
Reduce queries to public library/API concepts; remove private source snippets,
internal names/URLs, customer or personal data, credentials and confidential
task details. Do not blindly forward prompts, logs, stack traces or code.
If a useful query cannot be sanitized to approved public information, do not
send it; obtain explicit authorization for that data or use an approved local
source. Do not claim an automatic code-exclusion or sanitization guarantee.

## Open Questions

- [ ] Verify .NET / EF Core / Angular coverage quality with manual testing
- [ ] Check rate limits on free tier for typical daily usage
- [ ] Evaluate whether Copilot's built-in knowledge is sufficient for our stack without Context7
- [ ] Approve provider/transport, query data classes and request metadata under corporate policy
- [ ] Verify argument sanitization, retention/telemetry and credential handling against the version proposed for adoption

## Decision

Deferred — pending manual research and evaluation.
