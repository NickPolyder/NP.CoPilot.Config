<#
.SYNOPSIS
    Deploys the MCP server stack to a target host via Docker Compose.

.DESCRIPTION
    Copies the Docker Compose file, SearXNG settings, and environment file to a
    target host, then runs 'docker compose up -d' to start or update the stack.

    Supports three deployment modes:
      - Remote  — SSH/SCP to a remote host (default, e.g. Raspberry Pi)
      - Local   — Copies files locally and runs docker compose on the host machine
      - WSL     — Copies files into a WSL distribution and runs docker compose there

    The script is idempotent — safe to run repeatedly. It will pull latest images
    and recreate only containers whose configuration has changed.

.PARAMETER DeployMode
    Where to deploy: Remote (SSH/SCP), Local (this machine), or WSL. Default: Remote.

.PARAMETER TargetHost
    Hostname or IP of the remote machine. Only used in Remote mode. Default: raspberrypi.

.PARAMETER User
    SSH user on the remote machine. Only used in Remote mode. Default: pi.

.PARAMETER RemotePath
    Directory on the target where files are deployed.
    Defaults: Remote/WSL = ~/DockerScripts, Local = ~/DockerScripts (resolved to $HOME).

.PARAMETER WslDistro
    WSL distribution name. Only used in WSL mode. If omitted, uses the default distribution.

.PARAMETER ComposeFile
    Name of the compose file on the target. Default: mcps.docker-compose.yml.

.PARAMETER SkipCopy
    Skip the file copy step and only run docker compose (useful for restarting).

.PARAMETER WhatIf
    Shows what the script would do without making any changes.

.EXAMPLE
    .\deploy.ps1
    Deploys to pi@raspberrypi:~/DockerScripts via SSH (Remote mode).

.EXAMPLE
    .\deploy.ps1 -DeployMode Local -RemotePath C:\DockerScripts
    Deploys to C:\DockerScripts on this machine.

.EXAMPLE
    .\deploy.ps1 -DeployMode WSL
    Deploys to ~/DockerScripts in the default WSL distribution.

.EXAMPLE
    .\deploy.ps1 -DeployMode WSL -WslDistro Ubuntu-24.04
    Deploys to ~/DockerScripts in a specific WSL distribution.

.EXAMPLE
    .\deploy.ps1 -TargetHost 192.168.1.50 -User admin
    Deploys to admin@192.168.1.50:~/DockerScripts via SSH.

.EXAMPLE
    .\deploy.ps1 -WhatIf
    Shows what would happen without deploying.
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

    [switch]$SkipCopy
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot

# Resolve default RemotePath based on deploy mode
if (-not $RemotePath) {
    $RemotePath = switch ($DeployMode) {
        'Local' { Join-Path $HOME 'DockerScripts' }
        default { '~/DockerScripts' }
    }
}

function Write-Status($icon, $message) {
    Write-Host "  $icon $message"
}

# --- Transport: Remote (SSH/SCP) ---

function Invoke-RemoteCommand {
    param([string]$Command, [string]$Description)

    $sshTarget = "${User}@${TargetHost}"
    if ($PSCmdlet.ShouldProcess($TargetHost, $Description)) {
        Write-Status '🔧' $Description
        $output = ssh $sshTarget $Command 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ Remote command failed: $Description" -ForegroundColor Red
            Write-Host $output -ForegroundColor Red
            exit 1
        }
        if ($output) { Write-Host $output }
    }
}

function Copy-FileToRemote {
    param([string]$LocalPath, [string]$RemoteDestination, [string]$Description)

    if (-not (Test-Path $LocalPath)) {
        Write-Status '⚠️' "Source not found, skipping: $LocalPath"
        return
    }

    $sshTarget = "${User}@${TargetHost}"
    if ($PSCmdlet.ShouldProcess($RemoteDestination, "Copy $Description")) {
        Write-Status '📤' "Copying $Description → ${sshTarget}:${RemoteDestination}"
        scp $LocalPath "${sshTarget}:${RemoteDestination}" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ SCP failed for: $Description" -ForegroundColor Red
            exit 1
        }
    }
}

# --- Transport: Local ---

function Invoke-LocalCommand {
    param([string]$Command, [string]$Description)

    if ($PSCmdlet.ShouldProcess('localhost', $Description)) {
        Write-Status '🔧' $Description
        $output = Invoke-Expression $Command 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ Local command failed: $Description" -ForegroundColor Red
            Write-Host $output -ForegroundColor Red
            exit 1
        }
        if ($output) { Write-Host $output }
    }
}

function Copy-FileToLocal {
    param([string]$LocalPath, [string]$Destination, [string]$Description)

    if (-not (Test-Path $LocalPath)) {
        Write-Status '⚠️' "Source not found, skipping: $LocalPath"
        return
    }

    if ($PSCmdlet.ShouldProcess($Destination, "Copy $Description")) {
        Write-Status '📤' "Copying $Description → $Destination"
        Copy-Item -Path $LocalPath -Destination $Destination -Force
    }
}

# --- Transport: WSL ---

function Get-WslCommand {
    param([string]$Command)

    if ($WslDistro) {
        return "wsl -d $WslDistro -- bash -c `"$Command`""
    }
    return "wsl -- bash -c `"$Command`""
}

function Invoke-WslCommand {
    param([string]$Command, [string]$Description)

    $wslCmd = Get-WslCommand -Command $Command
    $target = if ($WslDistro) { "WSL ($WslDistro)" } else { 'WSL (default)' }

    if ($PSCmdlet.ShouldProcess($target, $Description)) {
        Write-Status '🔧' $Description
        $output = Invoke-Expression $wslCmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ WSL command failed: $Description" -ForegroundColor Red
            Write-Host $output -ForegroundColor Red
            exit 1
        }
        if ($output) { Write-Host $output }
    }
}

function Copy-FileToWsl {
    param([string]$LocalPath, [string]$RemoteDestination, [string]$Description)

    if (-not (Test-Path $LocalPath)) {
        Write-Status '⚠️' "Source not found, skipping: $LocalPath"
        return
    }

    $target = if ($WslDistro) { "WSL ($WslDistro)" } else { 'WSL (default)' }

    if ($PSCmdlet.ShouldProcess($RemoteDestination, "Copy $Description to $target")) {
        Write-Status '📤' "Copying $Description → ${target}:${RemoteDestination}"
        # Convert Windows path to a wslpath-accessible form, then use cp
        $winPath = (Resolve-Path $LocalPath).Path
        $cpCmd = "cp `"```$(wslpath '$winPath')`"`` `"$RemoteDestination`""
        $wslCmd = Get-WslCommand -Command $cpCmd
        $output = Invoke-Expression $wslCmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ WSL copy failed for: $Description" -ForegroundColor Red
            Write-Host $output -ForegroundColor Red
            exit 1
        }
    }
}

# --- Dispatch wrappers ---

function Invoke-TargetCommand {
    param([string]$Command, [string]$Description)

    switch ($DeployMode) {
        'Remote' { Invoke-RemoteCommand -Command $Command -Description $Description }
        'Local'  { Invoke-LocalCommand -Command $Command -Description $Description }
        'WSL'    { Invoke-WslCommand -Command $Command -Description $Description }
    }
}

function Copy-FileToTarget {
    param([string]$LocalPath, [string]$Destination, [string]$Description)

    switch ($DeployMode) {
        'Remote' { Copy-FileToRemote -LocalPath $LocalPath -RemoteDestination $Destination -Description $Description }
        'Local'  { Copy-FileToLocal -LocalPath $LocalPath -Destination $Destination -Description $Description }
        'WSL'    { Copy-FileToWsl -LocalPath $LocalPath -RemoteDestination $Destination -Description $Description }
    }
}

# --- Main ---

$targetLabel = switch ($DeployMode) {
    'Remote' { "${User}@${TargetHost}:${RemotePath}" }
    'Local'  { "localhost:${RemotePath}" }
    'WSL'    {
        $distroLabel = if ($WslDistro) { $WslDistro } else { 'default' }
        "WSL (${distroLabel}):${RemotePath}"
    }
}

Write-Host "`n🚀 Deploying MCP stack to $targetLabel" -ForegroundColor Cyan
Write-Host "   Mode: $DeployMode"
Write-Host "   Compose file: $ComposeFile`n"

# Ensure target directories exist
$mkdirCmd = switch ($DeployMode) {
    'Local' { "New-Item -ItemType Directory -Path '$RemotePath\searxng' -Force | Out-Null" }
    default { "mkdir -p $RemotePath/searxng" }
}
Invoke-TargetCommand -Command $mkdirCmd -Description "Ensure target directories exist"

if (-not $SkipCopy) {
    # Resolve compose destination
    $composeDestination = switch ($DeployMode) {
        'Local' { Join-Path $RemotePath $ComposeFile }
        default { "$RemotePath/$ComposeFile" }
    }

    # Copy compose file
    Copy-FileToTarget `
        -LocalPath (Join-Path $scriptDir 'docker-compose.yml') `
        -Destination $composeDestination `
        -Description 'docker-compose.yml'

    # Copy SearXNG settings
    $settingsDestination = switch ($DeployMode) {
        'Local' { Join-Path $RemotePath 'searxng' 'settings.yml' }
        default { "$RemotePath/searxng/settings.yml" }
    }
    Copy-FileToTarget `
        -LocalPath (Join-Path $scriptDir 'searxng' 'settings.yml') `
        -Destination $settingsDestination `
        -Description 'searxng/settings.yml'

    # Copy .env if it exists (not .env.example)
    $envFile = Join-Path $scriptDir '.env'
    if (Test-Path $envFile) {
        $envDestination = switch ($DeployMode) {
            'Local' { Join-Path $RemotePath '.env' }
            default { "$RemotePath/.env" }
        }
        Copy-FileToTarget `
            -LocalPath $envFile `
            -Destination $envDestination `
            -Description '.env'
    } else {
        Write-Status '⏭️' "No .env file found — using defaults. Copy .env.example to .env and configure if needed."
    }
}

# Docker compose commands — local mode runs directly, others go through transport
$composeCmd = switch ($DeployMode) {
    'Local' { "docker compose -f '$RemotePath\$ComposeFile'" }
    default { "cd $RemotePath && docker compose -f $ComposeFile" }
}

Invoke-TargetCommand `
    -Command "$composeCmd pull" `
    -Description "Pull latest container images"

Invoke-TargetCommand `
    -Command "$composeCmd up -d --remove-orphans" `
    -Description "Start MCP stack (docker compose up -d)"

Invoke-TargetCommand `
    -Command "$composeCmd ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'" `
    -Description "Verify running containers"

Write-Host "`n✅ MCP stack deployed successfully.`n" -ForegroundColor Green
