---
applyTo:
  - "docs/**/*.md"
---

# Markdown & Documentation Style

> Applies to project documentation under `docs/`. Keeps generated docs (features, bugs, infra, retrospectives) consistent.

- Start each document with a single `#` H1 title; don't skip heading levels.
- Keep line length reasonable; one sentence per line is fine for cleaner diffs.
- Use fenced code blocks with a language hint (```` ```csharp ````, ```` ```powershell ````).
- Use tables for trade-off comparisons and structured options (pros/cons, decision matrices).
- Use relative links for in-repo references so they survive moves and clones.
- Prefer descriptive link text over bare URLs.
- Use `-` for unordered lists consistently; reserve numbered lists for ordered steps.
- Reference code identifiers and paths in `inline code`.
- Keep documents focused — split large topics into linked files rather than one sprawling page.
- Date-stamp or version time-sensitive docs (retrospectives, decisions) so staleness is visible.
