#Requires -Version 7.0
<#
.SYNOPSIS
    Opts one checkout into the repository's Git pre-commit gate.
.DESCRIPTION
    Sets local core.hooksPath after checking the launcher and pwsh. On POSIX,
    runs checked chmod +x and verifies execute permission. Does not stage a mode
    change: a fresh checkout of a 100644 launcher needs this setup again.
#>

[CmdletBinding(SupportsShouldProcess)]
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'IsolatedProcess.psm1') -ErrorAction Stop
$context = New-IsolatedProcessContext
try {
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $discovery = Invoke-IsolatedProcess -Context $context -FilePath 'git' -WorkingDirectory $root `
        -ArgumentList @('-C', $root, 'rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($discovery.Stdout.Trim()) -ne $root) {
        throw 'RepositoryRoot must be the worktree root.'
    }
    foreach ($relative in @('.githooks', '.githooks\pre-commit', 'scripts', 'scripts\Invoke-ConfigPreCommitHook.ps1')) {
        $item = Get-Item -LiteralPath (Join-Path $root $relative) -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Hook setup refuses linked bootstrap paths: $relative"
        }
    }
    $hookPath = Join-Path $root '.githooks\pre-commit'
    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) { throw 'The pre-commit launcher is not a file.' }
    $null = Get-Command pwsh -CommandType Application -ErrorAction Stop
    if ($PSCmdlet.ShouldProcess($root, 'Enable the local Git pre-commit hook and POSIX execute permission')) {
        if (-not $IsWindows) {
            if (-not ([IO.File].GetMethods().Name -contains 'GetUnixFileMode')) {
                throw 'Checked POSIX hook setup requires PowerShell 7.3 or newer.'
            }
            $null = Invoke-IsolatedProcess -Context $context -FilePath 'chmod' -WorkingDirectory $root `
                -ArgumentList @('+x', '--', $hookPath)
            if (([int][IO.File]::GetUnixFileMode($hookPath) -band 64) -eq 0) {
                throw 'chmod succeeded but the hook is still not executable by its owner.'
            }
        }
        $null = Invoke-IsolatedProcess -Context $context -FilePath 'git' -WorkingDirectory $root `
            -ArgumentList @('-C', $root, 'config', '--local', 'core.hooksPath', '.githooks')
        $configured = Invoke-IsolatedProcess -Context $context -FilePath 'git' -WorkingDirectory $root `
            -ArgumentList @('-C', $root, 'config', '--local', '--get', 'core.hooksPath')
        if ($configured.Stdout.Trim() -cne '.githooks') { throw 'Local core.hooksPath verification failed.' }
        Write-Host '✅ Enabled the local Git hook; the Git index and tracked executable mode were not changed.' -ForegroundColor Green
    }
}
finally {
    Remove-IsolatedProcessContext -Context $context
}
