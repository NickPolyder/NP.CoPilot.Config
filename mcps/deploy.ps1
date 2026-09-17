#Requires -Version 7.0
<#
.SYNOPSIS
    Publishes and starts the isolated SearXNG Compose project, then waits for health.
.DESCRIPTION
    Remote uses SSH with stdin transfers; Local uses PowerShell file operations;
    WSL uses positional shell arguments and converts source paths inside WSL.
    Normal deployment deliberately recreates SearXNG, including settings-only
    updates. Images remain pinned. No orphan containers are removed.
.PARAMETER RemotePath
    Local directory, or an absolute/~/ path on the Remote/WSL target.
    Defaults to ~/DockerScripts. Paths may contain spaces and apostrophes.
.PARAMETER ComposeFile
    Destination filename (not a source path). Defaults to mcps.docker-compose.yml.
.PARAMETER ProjectName
    Explicit Compose project identity. Defaults to np-copilot-mcp.
    Older directory-derived projects require a separately planned migration.
.PARAMETER SkipCopy
    Validate and use deployed Compose, settings and private .env files.
    Reconciles with up, but does not restart an unchanged service.
.PARAMETER Restart
    Force recreation even with SkipCopy. Reapplies deployed settings/environment.
.PARAMETER EnvPolicy
    Preserve: copy source .env when present, otherwise require/preserve target .env.
    Require: require source .env. Reset: use example nonsecret defaults while
    retaining the existing target key. Require/Reset cannot be used with SkipCopy.
.PARAMETER RotateSecret
    Authorize replacing a different/legacy deployed key with a valid source key.
    Never generates a key. Cannot be combined with SkipCopy or EnvPolicy Reset.
.PARAMETER ReadinessTimeoutSeconds
    Maximum health-wait duration (default 180 seconds), including status commands.
.PARAMETER CommandTimeoutSeconds
    Timeout per other native command (default 300 seconds).
.EXAMPLE
    .\mcps\Initialize-Environment.ps1
    .\mcps\deploy.ps1 -WhatIf
.EXAMPLE
    .\mcps\deploy.ps1 -DeployMode Local -RemotePath "C:\DockerScripts\My stack"
.EXAMPLE
    .\mcps\deploy.ps1 -DeployMode WSL -WslDistro Ubuntu-24.04
.EXAMPLE
    .\mcps\deploy.ps1 -SkipCopy -Restart
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Remote', 'Local', 'WSL')]
    [string]$DeployMode = 'Remote',
    [Alias('ComputerName', 'Host')]
    [string]$TargetHost = 'raspberrypi',
    [string]$User = 'pi',
    [string]$RemotePath,
    [string]$WslDistro,
    [string]$ComposeFile = 'mcps.docker-compose.yml',
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')]
    [string]$ProjectName = 'np-copilot-mcp',
    [switch]$SkipCopy,
    [switch]$Restart,
    [ValidateSet('Preserve', 'Require', 'Reset')]
    [string]$EnvPolicy = 'Preserve',
    [switch]$RotateSecret,
    [ValidateRange(1, 3600)]
    [int]$ReadinessTimeoutSeconds = 180,
    [ValidateRange(1, 30)]
    [int]$ReadinessPollSeconds = 2,
    [ValidateRange(1, 3600)]
    [int]$CommandTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Mcp.Deployment.psm1') -ErrorAction Stop
    Invoke-McpDeployment @PSBoundParameters
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    if ($_.Exception.Data.Contains('ExitCode')) { exit [int]$_.Exception.Data['ExitCode'] }
    exit 1
}
