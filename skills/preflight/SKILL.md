---
name: preflight
description: >
  Validates the development environment and project health before starting work.
  Checks toolchain availability, project configuration, build status, and test
  baseline. Produces a go/no-go assessment.
tags:
  - environment
  - validation
  - preflight
  - setup
visibility: user
tools:
  [agent]
---

# Purpose

You are running a preflight check to verify the environment is ready for development.

Your goals are to:

- **Validate toolchain** — confirm required tools are installed and accessible.
- **Check project health** — verify the project builds and tests pass.
- **Surface blockers early** — catch configuration issues before work begins.
- **Produce a go/no-go** — clear assessment with actionable fixes for any issues.

---

# When to use this skill

Use this skill whenever:

- Starting work on a new or unfamiliar project.
- The user asks to "check my setup", "verify environment", or "preflight".
- Before a major implementation effort to confirm baseline health.
- After cloning a repo or switching branches.

Do **not** use this skill for:

- Debugging specific build failures — investigate those directly.
- CI/CD pipeline issues — those are a DevOps concern.

---

# Checks

Run these checks in order. Report results as they complete.

## 1. Global Toolchain

Verify these tools are available (run the version command for each):

| Tool | Check Command | Required |
|------|--------------|----------|
| Git | `git --version` | Always |
| .NET SDK | `dotnet --version` | If .cs files exist |
| Node.js | `node --version` | If package.json exists |
| npm/pnpm/yarn | `npm --version` (or equivalent) | If package.json exists |
| PowerShell | `$PSVersionTable.PSVersion` | Always (Windows) |
| Docker | `docker --version` | Only if docker-compose.yml or Dockerfile exists |

Skip tools that aren't relevant to the current project.

## 2. Project Configuration

- **Git status** — clean working tree? Uncommitted changes?
- **Branch** — which branch are we on? Is it up to date with remote?
- **Project config** — does `.github/instructions/project-config.instructions.md` exist? If yes, read it and summarize key settings.
- **Solution/project files** — can you find .sln, .csproj, package.json, or equivalent entry points?

## 3. Dependency Restore

Attempt to restore dependencies:

- .NET: `dotnet restore`
- Node: `npm install` (or equivalent from lock file)

Report success or failure with error details.

## 4. Build

Attempt to build the project:

- .NET: `dotnet build --no-restore`
- Node: `npm run build` (if build script exists)

Report success or failure. If build fails, summarize the top errors.

## 5. Test Baseline

Run the existing test suite:

- .NET: `dotnet test --no-build`
- Node: `npm test` (if test script exists)

Report: total tests, passed, failed, skipped. This establishes the baseline — any new failures after your changes are regressions.

---

# Output Format

Present results as a summary table:

```
### Preflight Results

| Check | Status | Details |
|-------|--------|---------|
| Git | ✅ Pass | v2.43.0, clean working tree, main branch |
| .NET SDK | ✅ Pass | 9.0.100 |
| Node.js | ⏭️ Skip | No package.json found |
| Restore | ✅ Pass | All packages restored |
| Build | ✅ Pass | 0 warnings, 0 errors |
| Tests | ⚠️ Warn | 142 passed, 3 skipped, 0 failed |

**Verdict: ✅ GO** — Environment is healthy. Ready to proceed.
```

Use these status indicators:

- ✅ **Pass** — check succeeded.
- ⚠️ **Warn** — non-blocking issue (e.g., skipped tests, minor warnings).
- ❌ **Fail** — blocking issue. Include fix instructions.
- ⏭️ **Skip** — not applicable to this project.

If any check fails, end with:

> **Verdict: ❌ NO-GO** — {N} blocking issue(s). Fix the items marked ❌ above before proceeding.
