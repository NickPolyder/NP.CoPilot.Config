---
applyTo: "**/*.ps1,**/*.psm1,**/*.psd1"
---

# PowerShell Style

- Use `$ErrorActionPreference = 'Stop'` at the top of scripts.
- Use `[CmdletBinding()]` and `param()` blocks for reusable scripts.
- Support `-WhatIf` / `ShouldProcess` for destructive operations.
- Use approved verbs for function names (`Get-`, `Set-`, `New-`, `Remove-`, etc.).
- Reuse the project's status/output helper and stream conventions.
- Handle errors explicitly — don't rely on silent failures.
- Use splatting for commands with many parameters.
- Prefer pipeline-friendly functions where applicable.
- Make automation idempotent; isolate regression fixtures from active installations.
