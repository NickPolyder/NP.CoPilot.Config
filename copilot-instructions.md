# Global Copilot Instructions

This is the root instruction file. Detailed instructions are split across the `instructions/` folder for maintainability. Both this file and the folder contents are loaded automatically.

## Quick Reference

- **Personality:** Senior engineer peer — direct, opinionated, enterprise-aware. See `instructions/personality.instructions.md`.
- **Workflow:** Tiered (Trivial / Standard / Full). See `instructions/workflow.instructions.md`.
- **Git:** Conventional commits, imperative mood, always include Co-authored-by trailer. See `instructions/git-conventions.instructions.md`.
- **Session:** Check for active work on start, summarize state on end. See `instructions/session-awareness.instructions.md`.
- **Coordination:** Strict hierarchy (User → Skill → Agent → Tools), structured handoffs. See `instructions/coordination.instructions.md`.
- **C# Style:** Microsoft conventions, file-scoped namespaces, var when obvious. See `instructions/csharp-style.instructions.md` (loads only for .cs files).
- **PowerShell Style:** ErrorActionPreference Stop, idempotent scripts, emoji status output. See `instructions/powershell-style.instructions.md` (loads only for .ps1 files).
- **Python Style:** PEP 8/257, type hints, ruff, pathlib, pytest. See `instructions/python-style.instructions.md` (loads only for .py files).
- **TypeScript & Node.js Style:** strict mode, ESM, Prettier/ESLint, LTS Node. See `instructions/typescript-style.instructions.md` (loads only for .ts/.js files).
- **SQL Style:** explicit columns, parameterized queries, set-based, indexed. See `instructions/sql-style.instructions.md` (loads only for .sql files).
- **Markdown & Docs Style:** H1 title, code fences, tables for trade-offs, relative links. See `instructions/markdown-style.instructions.md` (loads only for docs/**/*.md).
- **YAML & Docker Style:** 2-space indent, no secrets, pinned image tags, multi-stage builds. See `instructions/yaml-docker-style.instructions.md` (loads only for .yml/Dockerfile).
