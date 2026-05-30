---
applyTo:
  - "**/*.sql"
---

# SQL Style

> Engine-agnostic conventions. Prefer the dialect features of your target engine (T-SQL, PostgreSQL, etc.) where they improve clarity or performance.

- Uppercase SQL keywords (`SELECT`, `FROM`, `JOIN`); lowercase or consistent-case identifiers.
- Never use `SELECT *` in application or migration code — list columns explicitly.
- Always parameterize queries — never concatenate user input into SQL (prevents injection).
- Prefer set-based operations over row-by-row cursors/loops.
- Qualify columns with table aliases in multi-table queries; use short, meaningful aliases.
- Use explicit `JOIN` syntax with `ON` clauses — never comma-joins in the `FROM`.
- Index foreign keys and columns used in `WHERE` / `JOIN` / `ORDER BY`; avoid over-indexing write-heavy tables.
- Make schema migrations idempotent and reversible; never edit a migration that has shipped.
- Wrap multi-statement changes in transactions; keep transactions short to reduce lock contention.
- Avoid `NOLOCK` / dirty reads as a default performance fix — understand the isolation trade-off first.
- Name constraints and indexes explicitly (`PK_`, `FK_`, `IX_`) rather than relying on engine defaults.
- Prefer surrogate keys for identity, but enforce natural uniqueness with constraints.
- Keep business logic in the application layer; reserve stored procedures for set-based data operations.
