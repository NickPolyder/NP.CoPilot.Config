<#
.SYNOPSIS
    Symlinks Copilot CLI global config from this repo into ~/.copilot/.

.DESCRIPTION
    Creates symbolic links for copilot-instructions.md, agents/, and skills/
    from this repository to the ~/.copilot/ directory.

    Requires elevated permissions (Run as Administrator) on Windows to create
    symbolic links, unless Developer Mode is enabled.

.PARAMETER Mcp
    Also installs mcp-config.json for MCP server configuration (SearXNG search,
    Playwright browser). Only use this if you have the MCP stack deployed.

    If an existing mcp-config.json already exists at the target and is not a
    symlink, the script merges the mcpServers entries (existing entries win on
    conflict) and writes the merged result as a regular file. A backup of the
    original is created before merging.

.PARAMETER Uninstall
    Removes the symlinks created by this script.

.EXAMPLE
    .\install.ps1
    Creates symlinks for core config (instructions, agents, skills).

.EXAMPLE
    .\install.ps1 -Mcp
    Creates symlinks including MCP server configuration.

.EXAMPLE
    .\install.ps1 -Uninstall
    Removes symlinks.

.EXAMPLE
    .\install.ps1 -Uninstall -Mcp
    Removes symlinks including MCP configuration.
#>

param(
    [switch]$Mcp,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
$target = Join-Path $HOME '.copilot'

$links = @(
    @{ Name = 'copilot-instructions.md'; Type = 'File' }
    @{ Name = 'agents';                  Type = 'Directory' }
    @{ Name = 'skills';                  Type = 'Directory' }
)

if ($Mcp) {
    $links += @{ Name = 'mcp-config.json'; Type = 'File'; Mergeable = $true }
}

function Write-Status($icon, $message) {
    Write-Host "  $icon $message"
}

function Merge-McpConfig([string]$SourcePath, [string]$TargetPath) {
    try {
        $sourceJson = Get-Content $SourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $targetJson = Get-Content $TargetPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Status '❌' "Failed to parse JSON: $_"
        return $false
    }

    $sourceServers = $sourceJson.mcpServers
    $targetServers = $targetJson.mcpServers

    if ($null -eq $sourceServers) {
        Write-Status '⚠️' "Source has no mcpServers — nothing to merge"
        return $false
    }

    # Start with all target properties as the base
    $merged = $targetJson

    # Ensure target has an mcpServers object
    if ($null -eq $targetServers) {
        $merged | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $added = @()
    $skipped = @()

    foreach ($prop in $sourceServers.PSObject.Properties) {
        if ($merged.mcpServers.PSObject.Properties[$prop.Name]) {
            $skipped += $prop.Name
        }
        else {
            $merged.mcpServers | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            $added += $prop.Name
        }
    }

    # Backup the existing file
    $backupPath = "$TargetPath.backup"
    Copy-Item -Path $TargetPath -Destination $backupPath -Force
    Write-Status '📦' "Backed up existing config to: $backupPath"

    # Write merged result
    $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $TargetPath -Encoding UTF8 -NoNewline
    Write-Status '🔀' "Merged MCP config written to: $TargetPath"

    if ($added.Count -gt 0) {
        Write-Status '➕' "Added servers from repo: $($added -join ', ')"
    }
    if ($skipped.Count -gt 0) {
        Write-Status '⏭️' "Kept existing servers (conflict): $($skipped -join ', ')"
    }

    Write-Host ''
    Write-Host '  ⚠️  IMPORTANT: This is a merged file, not a symlink.' -ForegroundColor Yellow
    Write-Host '     Future changes to the repo config will NOT auto-flow.' -ForegroundColor Yellow
    Write-Host '     To restore live updates, remove the file and re-run install.' -ForegroundColor Yellow

    return $true
}

# Ensure ~/.copilot/ exists
if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Status '📁' "Created $target"
}

if ($Uninstall) {
    Write-Host "`n🗑️  Removing symlinks..." -ForegroundColor Yellow
    foreach ($link in $links) {
        $linkPath = Join-Path $target $link.Name
        if (Test-Path $linkPath) {
            $item = Get-Item $linkPath -Force
            if ($item.LinkType -eq 'SymbolicLink') {
                $item.Delete()
                Write-Status '✅' "Removed: $linkPath"
            } elseif ($link.Mergeable) {
                Write-Status '⚠️' "Skipped (merged file, not a symlink): $linkPath"
                Write-Host '     Delete manually if you want to remove it.' -ForegroundColor Yellow
            } else {
                Write-Status '⚠️' "Skipped (not a symlink): $linkPath"
            }
        } else {
            Write-Status '⏭️' "Not found: $linkPath"
        }
    }
    Write-Host "`n✅ Uninstall complete.`n" -ForegroundColor Green
    return
}

Write-Host "`n🔗 Installing Copilot global config symlinks..." -ForegroundColor Cyan
Write-Host "   Source: $source"
Write-Host "   Target: $target`n"

foreach ($link in $links) {
    $linkPath   = Join-Path $target $link.Name
    $sourcePath = Join-Path $source $link.Name

    if (-not (Test-Path $sourcePath)) {
        Write-Status '⚠️' "Source not found, skipping: $sourcePath"
        continue
    }

    # If the target exists as a regular file and this link supports merging, merge instead of symlink
    if ($link.Mergeable -and (Test-Path $linkPath)) {
        $existing = Get-Item $linkPath -Force
        if ($existing.LinkType -ne 'SymbolicLink') {
            $merged = Merge-McpConfig -SourcePath $sourcePath -TargetPath $linkPath
            if ($merged) { continue }
            Write-Status '⚠️' "Merge failed — falling back to symlink"
        }
    }

    # Remove existing item at link path
    if (Test-Path $linkPath) {
        $existing = Get-Item $linkPath -Force
        if ($existing.LinkType -eq 'SymbolicLink') {
            $existing.Delete()
            Write-Status '♻️' "Replaced existing symlink: $linkPath"
        } else {
            $backupPath = "$linkPath.backup"
            Move-Item -Path $linkPath -Destination $backupPath -Force
            Write-Status '📦' "Backed up existing item to: $backupPath"
        }
    }

    New-Item -ItemType SymbolicLink -Path $linkPath -Target $sourcePath | Out-Null
    Write-Status '✅' "$($link.Name) → $sourcePath"
}

Write-Host "`n✅ Installation complete. Copilot CLI will now use your global config.`n" -ForegroundColor Green
