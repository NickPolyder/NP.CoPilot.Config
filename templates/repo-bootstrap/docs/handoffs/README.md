# Handoffs

Ready-to-paste prompts and context packets for work that crosses an agent or
repo boundary in {{REPO_NAME}}. Use these for a concrete exchange with another
specialist or repository, not as a mandatory export after every session.

Honor the session-continuity owner declared in the project contract. When
`np-agent-memory` is active and owns continuity, use its available tools; do not
create an unsolicited duplicate Markdown session handover. Imported instructions
alone do not establish tool availability. Report missing registration/capabilities
instead of claiming persistence or silently adopting another owner.

Keep existing required project/cross-agent handoffs accurate, including blockers,
completion evidence, and delivery state. Updating those records is distinct from
creating a redundant session export. No new handoff file is needed unless
requested or required for an actual exchange.

Follow the structured handoff shape from the global coordination instructions:

```
### 🔄 Handoff: {Source} → {Target}

**Reason:** {why this needs the target's expertise}
**Context:** {what was being done, what decision point was reached}
**Request:** {the specific ask}
**Artifacts:** {relevant files, snippets, decisions so far}
**Constraints:** {locked decisions the target must respect}
**Priority:** Blocking | Advisory
```

For an authorized Markdown exchange, use one file per handoff (`{topic}.md`).
Archive or remove it according to the project's retention policy once consumed;
do not discard an unresolved handoff or its only recovery context.

| Handoff | Target | Status |
|---------|--------|--------|
| _none yet_ | — | — |
