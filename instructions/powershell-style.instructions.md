---
applyTo:
  - "**/*.ps1"
  - "**/*.psm1"
  - "**/*.psd1"
---

# PowerShell Style

> **Intent (anchor):** Apply PowerShell script style rules only to files matched by `applyTo`; project-specific script conventions win when more specific.

- Use `$ErrorActionPreference = 'Stop'` at the top of scripts.
- Use `[CmdletBinding()]` and `param()` blocks for reusable scripts.
- Prefer `-WhatIf` / `ShouldProcess` support for destructive operations.
- Use approved verbs for function names (`Get-`, `Set-`, `New-`, `Remove-`, etc.).
- Use Write-Host with emoji for user-facing status output (consistent with existing scripts in this repo).
- Handle errors explicitly — don't rely on silent failures.
- Use splatting for commands with many parameters.
- Prefer pipeline-friendly functions where applicable.
- Test scripts are idempotent — safe to re-run without side effects.

## Final Rules (Anchor)

Apply these rules only to PowerShell files: fail fast (`$ErrorActionPreference = 'Stop'`), make scripts idempotent, and use `ShouldProcess`/`-WhatIf` for destructive operations.
