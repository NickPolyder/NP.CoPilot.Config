<#
.SYNOPSIS
    Scaffolds Copilot project templates into a target repository.

.DESCRIPTION
    Copies project configuration templates from this repo into a target
    repository's .github/instructions/ directory — the path Copilot CLI
    reads for repo-level instructions.

    Optionally appends gitignore entries for local-only files.

.PARAMETER TargetPath
    Path to the target repository root. Defaults to current directory.

.PARAMETER SkipGitignore
    If set, skips appending gitignore entries.

.PARAMETER Force
    Overwrites existing files without prompting.

.EXAMPLE
    .\install-project.ps1 -TargetPath C:\Repos\MyProject

.EXAMPLE
    .\install-project.ps1
    Scaffolds into the current directory.
#>

param(
    [string]$TargetPath = (Get-Location).Path,
    [switch]$SkipGitignore,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$templateDir = Join-Path $PSScriptRoot 'templates'
$instructionsDir = Join-Path $TargetPath '.github' 'instructions'

function Write-Status($icon, $message) {
    Write-Host "  $icon $message"
}

# Validate target is a git repo
if (-not (Test-Path (Join-Path $TargetPath '.git'))) {
    Write-Host "`n❌ '$TargetPath' is not a git repository. Aborting.`n" -ForegroundColor Red
    exit 1
}

# Validate templates exist
if (-not (Test-Path $templateDir)) {
    Write-Host "`n❌ Templates directory not found at '$templateDir'. Aborting.`n" -ForegroundColor Red
    exit 1
}

Write-Host "`n📋 Installing Copilot project templates..." -ForegroundColor Cyan
Write-Host "   Source:  $templateDir"
Write-Host "   Target:  $TargetPath`n"

# Ensure .github/instructions/ exists
if (-not (Test-Path $instructionsDir)) {
    New-Item -ItemType Directory -Path $instructionsDir -Force | Out-Null
    Write-Status '📁' "Created $instructionsDir"
}

# Copy template files
$templates = @(
    'project-config.instructions.md'
    'local-preferences.instructions.md'
)

foreach ($file in $templates) {
    $sourcePath = Join-Path $templateDir $file
    $targetFilePath = Join-Path $instructionsDir $file

    if (-not (Test-Path $sourcePath)) {
        Write-Status '⚠️' "Template not found, skipping: $file"
        continue
    }

    if ((Test-Path $targetFilePath) -and -not $Force) {
        $response = Read-Host "  ⚠️  '$file' already exists. Overwrite? (y/N)"
        if ($response -ne 'y') {
            Write-Status '⏭️' "Skipped: $file"
            continue
        }
    }

    Copy-Item -Path $sourcePath -Destination $targetFilePath -Force
    Write-Status '✅' "$file → $targetFilePath"
}

# Append gitignore entries
if (-not $SkipGitignore) {
    $gitignorePath = Join-Path $TargetPath '.gitignore'
    $marker = '# Local Copilot preferences (personal, not shared)'
    $entry = '.github/instructions/local-preferences.instructions.md'

    $needsAppend = $true

    if (Test-Path $gitignorePath) {
        $content = Get-Content $gitignorePath -Raw
        if ($content -match [regex]::Escape($entry)) {
            $needsAppend = $false
            Write-Status '⏭️' ".gitignore already contains local preferences entry"
        }
    }

    if ($needsAppend) {
        $lines = @('', $marker, $entry)
        Add-Content -Path $gitignorePath -Value ($lines -join "`n")
        Write-Status '✅' "Appended local preferences entry to .gitignore"
    }
}

Write-Host "`n✅ Project templates installed.`n" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Edit .github/instructions/project-config.instructions.md with your project settings"
Write-Host "  2. Edit .github/instructions/local-preferences.instructions.md with your personal preferences"
Write-Host "  3. Commit project-config.instructions.md (local-preferences is gitignored)`n"
