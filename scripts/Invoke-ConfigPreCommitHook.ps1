#Requires -Version 7.0
<#
.SYNOPSIS
    Validates staged Copilot configuration changes before commit.

.DESCRIPTION
    Validates the complete captured index tree, including deletions and both
    sides of renames. The launcher, this driver, and its helper are worktree
    bootstrap code; validation inputs and the validator are snapshot-resident.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'GitSnapshot.psm1') -ErrorAction Stop
$candidate = $null
$exitCode = 0

try {
    $capture = @{ RepositoryRoot = $repositoryRoot; AllowEmpty = $true }
    if ($env:GIT_INDEX_FILE) {
        $capture.IndexPath = [IO.Path]::GetFullPath($env:GIT_INDEX_FILE, $repositoryRoot)
    }
    $candidate = New-GitReviewCandidate @capture
    foreach ($control in @(
        @{ Name = 'GIT_DIR'; Expected = $candidate.GitDirectory },
        @{ Name = 'GIT_WORK_TREE'; Expected = $repositoryRoot }
    )) {
        $value = [Environment]::GetEnvironmentVariable($control.Name)
        if ($value -and [IO.Path]::GetFullPath($value, $repositoryRoot) -ne [IO.Path]::GetFullPath($control.Expected)) {
            throw "Inherited $($control.Name) does not identify this hook's repository."
        }
    }
    $relevantPaths = @($candidate.ChangedPaths | Where-Object {
        $_ -match '^(?:\.githooks/|\.github/|agents/|instructions/|skills/|scripts/|tests/(?:ValidateConfig|GitCommitReviewSkill)/|mcps/|(?:\.gitattributes|\.gitmodules|mcp-config\.json|copilot-instructions\.md|README\.md)$)'
    })
    if ($relevantPaths.Count -gt 0) {
        $snapshot = New-GitTreeSnapshot -Candidate $candidate
        Write-Host '🔍 Validating staged Copilot configuration...' -ForegroundColor Cyan
        $result = Invoke-GitSnapshotCheck -Snapshot $snapshot -Name 'Configuration validation' `
            -FilePath (Get-Command pwsh -CommandType Application -ErrorAction Stop).Source `
            -ArgumentList @('-NoProfile', '-File', (Join-Path $snapshot.Path 'scripts\Validate-Config.ps1'), '-RepositoryRoot', $snapshot.Path) `
            -RequiredPaths @('scripts\Validate-Config.ps1')
        Write-Host $result.Output
        Assert-GitSnapshotIntegrity -Snapshot $snapshot
        Assert-GitCandidateCurrent -Candidate $candidate
    }
}
catch {
    Write-Host "❌ Configuration pre-commit gate failed: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
finally {
    if ($null -ne $candidate) { Remove-GitReviewCandidate -Candidate $candidate }
}

exit $exitCode
