---
applyTo: "**/*.sql"
---

# SQL Style

- Uppercase SQL keywords (`SELECT`, `FROM`, `JOIN`); lowercase or consistent-case identifiers.
- Never use `SELECT *` in application or migration code — list columns explicitly.
- Always parameterize queries — never concatenate user input into SQL (prevents injection).
- Prefer set-based operations over row-by-row cursors/loops.
- Qualify columns with table aliases in multi-table queries; use short, meaningful aliases.
- Use explicit `JOIN` syntax with `ON` clauses — never comma-joins in the `FROM`.
- Choose indexes from required constraints, query plans and measured workload.
- Plan migration sequencing and recovery; never edit a shipped migration or claim unverified reversibility.
- Use transactions where atomicity is required and supported; keep them short.
- Avoid `NOLOCK` / dirty reads as a default performance fix — understand the isolation trade-off first.
- Name constraints and indexes explicitly (`PK_`, `FK_`, `IX_`) rather than relying on engine defaults.
- Enforce required uniqueness with constraints and preserve the project's key strategy.
- Follow existing application/database ownership rather than relocating business logic by default.
