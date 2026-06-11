# ADR-{number}: {Title}

<!--
ADR template for {{REPO_NAME}}. Copy this file to {NNNN}-{kebab-case-title}.md
(zero-padded 4-digit number) and fill it in. For non-trivial decisions, prefer
running the `architecture-decision-record` skill, which uses this exact shape
and maintains the index below.
-->

**Status:** {Proposed | Accepted | Deprecated | Superseded by ADR-{N}}
**Date:** {YYYY-MM-DD}
**Decision Makers:** {who was involved}

## Context

{What is motivating this decision? Current state, requirements, constraints.}

## Decision Drivers

- {driver 1}
- {driver 2}

## Options Considered

### Option 1: {Name}

{Description.}

**Pros:**
- {advantage}

**Cons:**
- {disadvantage}

### Option 2: {Name}

{Description.}

**Pros:**
- {advantage}

**Cons:**
- {disadvantage}

## Decision Matrix

| Criterion | Weight | Option 1 | Option 2 |
|---|---|---|---|
| {criterion} | High/Med/Low | ✅/⚠️/❌ | ✅/⚠️/❌ |

## Decision

**Chosen option: {Option N} — {title}**

{Justification — why this option, referencing the drivers and matrix.}

## Consequences

### Positive
- {positive consequence}

### Negative
- {trade-off} — Mitigation: {how to manage it}

### Risks
- {risk} — Mitigation: {how to manage it}

## When we'd revisit

- {explicit trigger that would justify reopening this decision}

## Related

- {links to related ADRs, docs, tickets}
