#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a private mcps\.env with a persistent random SearXNG key.
.DESCRIPTION
    Uses .env.example for a new file and preserves existing nonsecret settings.
    A valid existing key is retained unless RotateSecret is explicit. Values
    are never printed. This does not deploy or change any running service.
.PARAMETER RotateSecret
    Replace an existing key. Deploy the changed file with deploy.ps1 -RotateSecret.
.EXAMPLE
    .\mcps\Initialize-Environment.ps1 -WhatIf
.EXAMPLE
    .\mcps\Initialize-Environment.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param([switch]$RotateSecret)

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Mcp.Deployment.psm1') -ErrorAction Stop
    Initialize-McpEnvironment @PSBoundParameters
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    if ($_.Exception.Data.Contains('ExitCode')) { exit [int]$_.Exception.Data['ExitCode'] }
    exit 1
}
