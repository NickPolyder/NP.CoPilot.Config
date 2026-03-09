<#
.SYNOPSIS
    Symlinks Copilot CLI global config from this repo into ~/.copilot/.

.DESCRIPTION
    Creates symbolic links for copilot-instructions.md, agents/, and skills/
    from this repository to the ~/.copilot/ directory.

    Requires elevated permissions (Run as Administrator) on Windows to create
    symbolic links, unless Developer Mode is enabled.

.PARAMETER Uninstall
    Removes the symlinks created by this script.

.EXAMPLE
    .\install.ps1
    Creates symlinks.

.EXAMPLE
    .\install.ps1 -Uninstall
    Removes symlinks.
#>

param(
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

function Write-Status($icon, $message) {
    Write-Host "  $icon $message"
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
