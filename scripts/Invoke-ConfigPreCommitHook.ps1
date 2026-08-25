#Requires -Version 7.0
<#
.SYNOPSIS
    Validates staged Copilot configuration changes before commit.

.DESCRIPTION
    Materializes the Git index into a temporary snapshot and runs the structural
    validator against that snapshot. Unstaged worktree changes never affect the
    hook result.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$gitRoot = (& git -C $repositoryRoot rev-parse --show-toplevel).Trim()
if ([string]::IsNullOrWhiteSpace($gitRoot)) {
    throw 'The configuration pre-commit hook source must be inside a Git repository.'
}

$changedPaths = @(
    & git -C $repositoryRoot diff --cached --name-only --diff-filter=ACMR |
        Where-Object {
            $_ -match '^(?:\.githooks/|\.github/|agents/|instructions/|skills/|scripts/|tests/ValidateConfig/|mcp-config\.json$|mcps/|README\.md$)'
        }
)

if ($changedPaths.Count -eq 0) {
    exit 0
}

$snapshotPath = Join-Path ([System.IO.Path]::GetTempPath()) "np-copilot-config-index-$([guid]::NewGuid())"
$archivePath = "$snapshotPath.zip"

try {
    New-Item -ItemType Directory -Path $snapshotPath -Force | Out-Null

    $tree = (& git -C $repositoryRoot write-tree).Trim()
    if ([string]::IsNullOrWhiteSpace($tree)) {
        throw 'Unable to resolve the staged Git tree for configuration validation.'
    }

    & git -C $repositoryRoot archive --format=zip --output=$archivePath $tree
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to materialize the staged Git tree for configuration validation.'
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $snapshotPath -Force

    Write-Host '🔍 Validating staged Copilot configuration...' -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $snapshotPath 'scripts/Validate-Config.ps1') -RepositoryRoot $snapshotPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Staged Copilot configuration validation failed. Fix the reported findings before committing.'
    }
}
finally {
    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $snapshotPath) {
        Remove-Item -LiteralPath $snapshotPath -Recurse -Force
    }
}

exit 0
