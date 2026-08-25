#Requires -Version 7.0
<#
.SYNOPSIS
    Scaffolds Copilot project templates into a target repository, or safely
    removes a prior installation.

.DESCRIPTION
    Copies project configuration templates from this repo into a target
    repository's .github/instructions/ directory — the path Copilot CLI
    reads for repo-level instructions — and optionally appends gitignore
    entries for local-only files.

    The installer is transactional and non-interactive (it never prompts):
    every existing file it is about to overwrite is backed up to a unique,
    timestamped folder first, and an install manifest recorded under
    .np-copilot-project-installer/ tracks exactly what this script owns, so
    a later -Uninstall can safely restore prior content. A file the script
    does not recognize as its own prior write (i.e. one you have edited, or
    one that already existed before the first install) is never touched
    unless -Force is supplied — and even then it is backed up first.

    Re-running the installer is always safe:
      - Missing files are installed.
      - Files that already match the current template are left alone.
      - Files this installer previously wrote, and that you have not since
        edited, are refreshed to match the current template automatically
        (no -Force required — the repository owns this content).
      - Files that differ from what this installer would write, and were
        not its last recorded write (your own edits, or a pre-existing user
        file), are left in place and reported, unless -Force is supplied.

.PARAMETER TargetPath
    Path to the target repository root. Defaults to current directory.
    Must be a git repository (a .git entry must exist at this path).
    This same parameter doubles as the test seam for isolated test runs —
    point it at a disposable temporary git repository to exercise the
    installer without touching a real project.

.PARAMETER Template
    Framework-specific template variant. Options: Generic, Angular, Blazor, ServiceFabric.
    Default: Generic.

.PARAMETER SkipGitignore
    If set, skips appending gitignore entries.

.PARAMETER Force
    Overwrites files that exist with content this installer did not write
    (your own edits, or a pre-existing file at the same path). The previous
    content is always backed up first, so the change can be undone with
    -Uninstall. Files this installer already owns and that you have not
    edited are refreshed automatically without needing -Force.

.PARAMETER Uninstall
    Removes files this installer owns and that you have not since edited,
    restoring any backed-up prior content in their place. Files you have
    modified since the last install/repair are left in place with recovery
    guidance instead of being deleted. Also removes the gitignore block this
    installer added, if it is still present unmodified.

.EXAMPLE
    .\install-project.ps1 -TargetPath C:\Repos\MyProject

.EXAMPLE
    .\install-project.ps1 -Template Angular -TargetPath C:\Repos\MyAngularApp

.EXAMPLE
    .\install-project.ps1 -Template Blazor

.EXAMPLE
    .\install-project.ps1 -Template ServiceFabric -TargetPath C:\Repos\MySFApp

.EXAMPLE
    .\install-project.ps1
    Scaffolds the generic template into the current directory.

.EXAMPLE
    .\install-project.ps1 -TargetPath C:\Repos\MyProject -Force
    Re-scaffolds even if the target files were hand-edited. The previous
    content is backed up first and can be recovered with -Uninstall.

.EXAMPLE
    .\install-project.ps1 -TargetPath C:\Repos\MyProject -WhatIf
    Shows exactly what would be created, refreshed, or backed up, without
    making any changes.

.EXAMPLE
    .\install-project.ps1 -TargetPath C:\Repos\MyProject -Uninstall
    Removes the installer-owned files and gitignore entries, restoring any
    backed-up prior content.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Install')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Uninstall',
    Justification = 'Used as a parameter-set discriminator via $PSCmdlet.ParameterSetName, not read directly.')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$TargetPath = (Get-Location).Path,

    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('Generic', 'Angular', 'Blazor', 'ServiceFabric')]
    [string]$Template = 'Generic',

    [Parameter(ParameterSetName = 'Install')]
    [switch]$SkipGitignore,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory)]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$script:StateDirName = '.np-copilot-project-installer'
$script:RunStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$script:GitignoreMarker = '# Local Copilot preferences (personal, not shared)'
$script:GitignoreEntry = '.github/instructions/local-preferences.instructions.md'

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Write-Status {
    param(
        [Parameter(Mandatory)][string]$Icon,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host "  $Icon $Message"
}

function Get-Sha256FileHash {
    <#
    .SYNOPSIS
        Returns the SHA-256 hex hash of a file's raw bytes, or $null if the
        file does not exist. Used to detect whether installer-owned content
        has been changed since the last managed write.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

function Get-StateDir {
    param([Parameter(Mandatory)][string]$TargetPath)
    Join-Path $TargetPath $script:StateDirName
}

function Get-ManifestPath {
    param([Parameter(Mandatory)][string]$TargetPath)
    Join-Path (Get-StateDir -TargetPath $TargetPath) 'manifest.json'
}

function Import-ProjectManifest {
    param([Parameter(Mandatory)][string]$TargetPath)
    $manifestPath = Get-ManifestPath -TargetPath $TargetPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
    try {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch {
        Write-Status '⚠️' "Existing manifest at $manifestPath is unreadable ($($_.Exception.Message)); treating as absent."
        $null
    }
}

function New-ProjectManifestObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only; performs no I/O or state mutation. Save-ProjectManifest is the ShouldProcess-gated write.')]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][array]$Artifacts,
        [bool]$GitignoreManaged,
        [bool]$InstructionsDirCreatedByUs,
        $ExistingManifest
    )

    $createdAt = if ($ExistingManifest -and $ExistingManifest.CreatedAt) { $ExistingManifest.CreatedAt } else { (Get-Date).ToUniversalTime().ToString('o') }

    [pscustomobject]@{
        SchemaVersion              = 1
        TargetPath                 = $TargetPath
        Template                   = $Template
        CreatedAt                  = $createdAt
        UpdatedAt                  = (Get-Date).ToUniversalTime().ToString('o')
        GitignoreManaged           = $GitignoreManaged
        InstructionsDirCreatedByUs = $InstructionsDirCreatedByUs
        Artifacts                  = $Artifacts
    }
}

function Save-ProjectManifest {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )
    if ($PSCmdlet.ShouldProcess($ManifestPath, 'Write install manifest')) {
        $dir = Split-Path $ManifestPath -Parent
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        ($Manifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $ManifestPath -Encoding utf8 -NoNewline
    }
}

# ---------------------------------------------------------------------------
# Transaction log (created-this-run artifacts only; rolled back on failure)
# ---------------------------------------------------------------------------

$script:TxLog = [System.Collections.Generic.List[object]]::new()

function Undo-Transaction {
    <#
    .SYNOPSIS
        Reverses every action recorded in $script:TxLog, in reverse order,
        so a failed run leaves the target exactly as it was found.
    #>
    if (-not $script:TxLog -or $script:TxLog.Count -eq 0) { return }

    Write-Host "`n↩️  Rolling back changes made during this run..." -ForegroundColor Yellow
    for ($i = $script:TxLog.Count - 1; $i -ge 0; $i--) {
        $entry = $script:TxLog[$i]
        try {
            switch ($entry.Action) {
                'CreatedDirectory' {
                    Remove-Item -LiteralPath $entry.Path -Force -Recurse -ErrorAction SilentlyContinue
                }
                'WroteFile' {
                    if ($entry.PreviousContentPath -and (Test-Path -LiteralPath $entry.PreviousContentPath)) {
                        Move-Item -LiteralPath $entry.PreviousContentPath -Destination $entry.Path -Force
                    }
                    else {
                        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
                    }
                }
                'AppendedGitignore' {
                    if ($null -eq $entry.PreviousContent) {
                        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Set-Content -LiteralPath $entry.Path -Value $entry.PreviousContent -Encoding utf8 -NoNewline
                    }
                }
            }
            Write-Status '↩️' "Reverted $($entry.Action): $($entry.Path)"
        }
        catch {
            Write-Status '❌' "Rollback step failed for $($entry.Path): $($_.Exception.Message)"
        }
    }

    if ($script:RunBackupDir -and (Test-Path -LiteralPath $script:RunBackupDir)) {
        $leftoverFiles = Get-ChildItem -LiteralPath $script:RunBackupDir -Force -Recurse -File -ErrorAction SilentlyContinue
        if (-not $leftoverFiles) {
            Remove-Item -LiteralPath $script:RunBackupDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    # If this was a brand-new target (no prior manifest.json, no prior backups),
    # a failed run should leave absolutely no trace — prune the whole state
    # directory tree once it contains nothing but empty folders.
    if ($script:RunStateDir -and (Test-Path -LiteralPath $script:RunStateDir)) {
        $anyFileAnywhere = Get-ChildItem -LiteralPath $script:RunStateDir -Force -Recurse -File -ErrorAction SilentlyContinue
        if (-not $anyFileAnywhere) {
            Remove-Item -LiteralPath $script:RunStateDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

function Test-ProjectInstallPreflight {
    <#
    .SYNOPSIS
        Validates the target repo and every template source file needed for
        the requested template before any mutation happens. Returns the
        resolved list of install items (skipping any individually-missing
        optional template, with a warning) or throws with an aggregated
        message if a hard requirement (git repo, templates dir) fails.
    #>
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TemplateDir,
        [Parameter(Mandatory)][string]$Template
    )

    $problems = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        $problems.Add("Target path does not exist: $TargetPath")
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $TargetPath '.git'))) {
        $problems.Add("'$TargetPath' is not a git repository (no .git found).")
    }

    if (-not (Test-Path -LiteralPath $TemplateDir -PathType Container)) {
        $problems.Add("Templates directory not found at '$TemplateDir'.")
    }

    if ($problems.Count -gt 0) {
        throw "Preflight failed with $($problems.Count) problem(s): `n - " + ($problems -join "`n - ")
    }

    $projectConfigFile = switch ($Template) {
        'Angular' { 'project-config-angular.instructions.md' }
        'Blazor' { 'project-config-blazor.instructions.md' }
        'ServiceFabric' { 'project-config-service-fabric.instructions.md' }
        default { 'project-config.instructions.md' }
    }

    $items = @(
        @{ Source = $projectConfigFile; Target = 'project-config.instructions.md' }
        @{ Source = 'local-preferences.instructions.md'; Target = 'local-preferences.instructions.md' }
    )

    $resolved = @()
    foreach ($item in $items) {
        $sourcePath = Join-Path $TemplateDir $item.Source
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            Write-Status '⚠️' "Template not found, skipping: $($item.Source)"
            continue
        }
        $resolved += [pscustomobject]@{ Name = $item.Target; SourcePath = $sourcePath }
    }

    return $resolved
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

function New-ArtifactBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupDir
    )

    $name = Split-Path $Path -Leaf
    $destination = Join-Path $BackupDir $name

    if ($PSCmdlet.ShouldProcess($Path, "Back up to $destination")) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination $destination -Force
        Write-Status '📦' "Backed up existing file to: $destination"
    }

    return $destination
}

function Install-ProjectFile {
    <#
    .SYNOPSIS
        Installs a single template file, classifying the target's current
        state (missing / up to date / safe-to-refresh / conflict) and
        acting accordingly. Never overwrites content this installer did not
        write unless -Force is supplied, and always backs up what it
        replaces first.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$BackupDir,
        [switch]$Force,
        $PreviousArtifact
    )

    $sourceHash = Get-Sha256FileHash -Path $SourcePath
    $carriedBackupPath = if ($PreviousArtifact) { $PreviousArtifact.BackupPath } else { $null }

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($TargetPath, "Install $Name")) {
            $dir = Split-Path $TargetPath -Parent
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $null })
            Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
        }
        Write-Status '✅' "$Name -> installed"
        return [pscustomobject]@{
            Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath
            InstalledHash = $sourceHash; Status = 'Managed'
        }
    }

    $currentHash = Get-Sha256FileHash -Path $TargetPath

    if ($currentHash -eq $sourceHash) {
        Write-Status '✅' "$Name already up to date."
        return [pscustomobject]@{
            Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath
            InstalledHash = $currentHash; Status = 'Managed'
        }
    }

    $ownedUnmodified = $PreviousArtifact -and ($PreviousArtifact.Status -eq 'Managed') -and ($currentHash -eq $PreviousArtifact.InstalledHash)

    if ($ownedUnmodified -or $Force) {
        $verb = if ($ownedUnmodified) { 'Refresh' } else { 'Overwrite' }
        if ($PSCmdlet.ShouldProcess($TargetPath, "$verb $Name")) {
            # Always take a fresh, this-run backup so a mid-transaction
            # failure can roll back to exactly what was here a moment ago
            # (TxLog). Whether it also becomes the manifest's restore point
            # depends on what it is a backup OF:
            $runBackupPath = New-ArtifactBackup -Path $TargetPath -BackupDir $BackupDir
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $runBackupPath })
            Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
            if ($ownedUnmodified) {
                # Refreshing installer-owned content: this backup is of our
                # OWN previous template output, not foreign/pre-install
                # content. It must never become — or replace — the
                # manifest's restore point, which must carry forward
                # unchanged (staying $null for artifacts the installer
                # itself first created).
                $backupPath = $carriedBackupPath
            }
            else {
                # First time this path's foreign content (pre-existing, or
                # user-edited since the last managed write) is being backed
                # up under -Force: that backup IS the restore point, unless
                # an earlier one was already recorded — carry that forward
                # instead of clobbering it.
                $backupPath = if ($carriedBackupPath) { $carriedBackupPath } else { $runBackupPath }
            }
        }
        else {
            $backupPath = $carriedBackupPath
        }
        if ($ownedUnmodified) {
            Write-Status '🔄' "$Name refreshed to current template."
        }
        else {
            Write-Status '✅' "$Name overwritten (-Force); previous content backed up."
        }
        return [pscustomobject]@{
            Name = $Name; TargetPath = $TargetPath; BackupPath = $backupPath
            InstalledHash = $sourceHash; Status = 'Managed'
        }
    }

    Write-Status '⚠️' "$Name already exists with different content; leaving as-is. Use -Force to overwrite (a backup will be made first)."
    return [pscustomobject]@{
        Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath
        InstalledHash = $currentHash; Status = 'Conflict'
    }
}

function Set-GitignoreEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$GitignorePath
    )

    $existingContent = $null
    $alreadyPresent = $false

    if (Test-Path -LiteralPath $GitignorePath -PathType Leaf) {
        $existingContent = Get-Content -LiteralPath $GitignorePath -Raw -Encoding utf8
        if ($existingContent -match [regex]::Escape($script:GitignoreEntry)) {
            $alreadyPresent = $true
        }
    }

    if ($alreadyPresent) {
        Write-Status '⏭️' '.gitignore already contains the local preferences entry.'
        return $true
    }

    if ($PSCmdlet.ShouldProcess($GitignorePath, 'Append local preferences entry to .gitignore')) {
        $lines = @('', $script:GitignoreMarker, $script:GitignoreEntry)
        Add-Content -LiteralPath $GitignorePath -Value ($lines -join "`n") -Encoding utf8
        $script:TxLog.Add(@{ Action = 'AppendedGitignore'; Path = $GitignorePath; PreviousContent = $existingContent })
        Write-Status '✅' 'Appended local preferences entry to .gitignore.'
    }
    return $true
}

function Invoke-ProjectInstall {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TemplateDir,
        [Parameter(Mandatory)][string]$Template,
        [switch]$SkipGitignore,
        [switch]$Force
    )

    Write-Host "`n📋 Installing Copilot project templates..." -ForegroundColor Cyan
    Write-Host "   Source:  $TemplateDir"
    Write-Host "   Target:  $TargetPath`n"

    Write-Host '🔍 Preflight checks...'
    $items = Test-ProjectInstallPreflight -TargetPath $TargetPath -TemplateDir $TemplateDir -Template $Template
    Write-Status '✅' 'Preflight checks passed.'

    $existingManifest = Import-ProjectManifest -TargetPath $TargetPath
    $instructionsDir = Join-Path $TargetPath '.github' 'instructions'
    $stateDir = Get-StateDir -TargetPath $TargetPath
    $backupDir = Join-Path $stateDir "backups\$script:RunStamp"
    $script:RunBackupDir = $backupDir
    $script:RunStateDir = $stateDir

    $instructionsDirCreatedByUs = $existingManifest -and $existingManifest.InstructionsDirCreatedByUs
    if (-not (Test-Path -LiteralPath $instructionsDir)) {
        if ($PSCmdlet.ShouldProcess($instructionsDir, 'Create instructions directory')) {
            New-Item -ItemType Directory -Path $instructionsDir -Force | Out-Null
            $script:TxLog.Add(@{ Action = 'CreatedDirectory'; Path = $instructionsDir })
        }
        $instructionsDirCreatedByUs = $true
    }

    $artifacts = @()
    try {
        foreach ($item in $items) {
            $prevArtifact = $null
            if ($existingManifest) {
                $prevArtifact = @($existingManifest.Artifacts) | Where-Object { $_.Name -eq $item.Name } | Select-Object -First 1
            }
            $targetFilePath = Join-Path $instructionsDir $item.Name
            $artifact = Install-ProjectFile -Name $item.Name -SourcePath $item.SourcePath -TargetPath $targetFilePath `
                -BackupDir $backupDir -Force:$Force -PreviousArtifact $prevArtifact
            $artifacts += $artifact
        }

        $gitignoreManaged = $existingManifest -and $existingManifest.GitignoreManaged
        if (-not $SkipGitignore) {
            $gitignorePath = Join-Path $TargetPath '.gitignore'
            $gitignoreManaged = Set-GitignoreEntry -GitignorePath $gitignorePath
        }
    }
    catch {
        Write-Status '❌' "Install step failed: $($_.Exception.Message)"
        Undo-Transaction
        throw
    }

    if ($WhatIfPreference) {
        Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
        return
    }

    $manifest = New-ProjectManifestObject -TargetPath $TargetPath -Template $Template -Artifacts $artifacts `
        -GitignoreManaged ([bool]$gitignoreManaged) -InstructionsDirCreatedByUs ([bool]$instructionsDirCreatedByUs) `
        -ExistingManifest $existingManifest
    Save-ProjectManifest -Manifest $manifest -ManifestPath (Get-ManifestPath -TargetPath $TargetPath)

    $conflicts = @($artifacts | Where-Object { $_.Status -eq 'Conflict' })
    if ($conflicts.Count -gt 0) {
        Write-Status '⚠️' "Left unchanged (differs from template, use -Force to overwrite): $($conflicts.Name -join ', ')"
    }

    Write-Host "`n✅ Project templates installed (template: $Template).`n" -ForegroundColor Green
    Write-Host 'Next steps:' -ForegroundColor Yellow
    Write-Host '  1. Edit .github/instructions/project-config.instructions.md with your project settings'
    Write-Host '  2. Edit .github/instructions/local-preferences.instructions.md with your personal preferences'
    Write-Host "  3. Commit project-config.instructions.md (local-preferences is gitignored)`n"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

function Remove-GitignoreEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$GitignorePath)

    if (-not (Test-Path -LiteralPath $GitignorePath -PathType Leaf)) { return $true }

    $content = Get-Content -LiteralPath $GitignorePath -Raw -Encoding utf8
    $block = "`n$script:GitignoreMarker`n$script:GitignoreEntry"
    $blockNoLeadingNewline = "$script:GitignoreMarker`n$script:GitignoreEntry"

    if ($content.Contains($block)) {
        if ($PSCmdlet.ShouldProcess($GitignorePath, 'Remove local preferences entry from .gitignore')) {
            $updated = $content.Replace($block, '')
            Set-Content -LiteralPath $GitignorePath -Value $updated -Encoding utf8 -NoNewline
            Write-Status '➖' 'Removed local preferences entry from .gitignore.'
        }
        return $true
    }
    elseif ($content.Contains($blockNoLeadingNewline)) {
        if ($PSCmdlet.ShouldProcess($GitignorePath, 'Remove local preferences entry from .gitignore')) {
            $updated = $content.Replace($blockNoLeadingNewline, '')
            Set-Content -LiteralPath $GitignorePath -Value $updated -Encoding utf8 -NoNewline
            Write-Status '➖' 'Removed local preferences entry from .gitignore.'
        }
        return $true
    }

    Write-Status 'ℹ️' 'Gitignore entry not found verbatim (edited or already removed); leaving .gitignore untouched.'
    return $false
}

function Invoke-ProjectUninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TargetPath)

    Write-Host "`n🗑️  Uninstalling Copilot project templates..." -ForegroundColor Cyan
    Write-Host "   Target: $TargetPath`n"

    $manifest = Import-ProjectManifest -TargetPath $TargetPath
    $instructionsDir = Join-Path $TargetPath '.github' 'instructions'

    if (-not $manifest) {
        Write-Status 'ℹ️' 'No installer manifest found; nothing tracked to uninstall.'
        Write-Status 'ℹ️' "If files remain at $instructionsDir, remove them manually after reviewing their content."
        return
    }

    $remainingArtifacts = @()
    $anyConflict = $false

    foreach ($artifact in @($manifest.Artifacts)) {
        $path = $artifact.TargetPath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $currentHash = Get-Sha256FileHash -Path $path
        if ($currentHash -ne $artifact.InstalledHash) {
            Write-Status '⚠️' "$($artifact.Name) has been modified since install; leaving it in place. Recovery: compare with backup at $($artifact.BackupPath)."
            $remainingArtifacts += $artifact
            $anyConflict = $true
            continue
        }

        if ($PSCmdlet.ShouldProcess($path, 'Remove installer-managed file')) {
            Remove-Item -LiteralPath $path -Force
            Write-Status '✅' "Removed: $path"

            if ($artifact.BackupPath -and (Test-Path -LiteralPath $artifact.BackupPath)) {
                Copy-Item -LiteralPath $artifact.BackupPath -Destination $path -Force
                Write-Status '♻️' "Restored previous content to $path"
            }
        }
    }

    $gitignoreRemoved = $true
    if ($manifest.GitignoreManaged) {
        $gitignorePath = Join-Path $TargetPath '.gitignore'
        $gitignoreRemoved = Remove-GitignoreEntry -GitignorePath $gitignorePath
        if (-not $gitignoreRemoved) { $anyConflict = $true }
    }
    $gitignoreStillManaged = $manifest.GitignoreManaged -and -not $gitignoreRemoved

    if (-not $anyConflict -and $manifest.InstructionsDirCreatedByUs -and (Test-Path -LiteralPath $instructionsDir)) {
        $remaining = Get-ChildItem -LiteralPath $instructionsDir -Force -ErrorAction SilentlyContinue
        if (-not $remaining) {
            if ($PSCmdlet.ShouldProcess($instructionsDir, 'Remove empty instructions directory')) {
                Remove-Item -LiteralPath $instructionsDir -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    $stateDir = Get-StateDir -TargetPath $TargetPath
    if ($WhatIfPreference) {
        Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
        return
    }

    if ($anyConflict) {
        $trimmed = New-ProjectManifestObject -TargetPath $TargetPath -Template $manifest.Template -Artifacts $remainingArtifacts `
            -GitignoreManaged ([bool]$gitignoreStillManaged) -InstructionsDirCreatedByUs ([bool]$manifest.InstructionsDirCreatedByUs) `
            -ExistingManifest $manifest
        Save-ProjectManifest -Manifest $trimmed -ManifestPath (Get-ManifestPath -TargetPath $TargetPath)
        Write-Host "`n⚠️  Uninstall finished; some items needed manual attention and were left in place.`n" -ForegroundColor Yellow
    }
    else {
        Remove-Item -LiteralPath $stateDir -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "`n✅ Uninstall complete. Installer state removed.`n" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$script:RunBackupDir = $null
$script:RunStateDir = $null
$templateDir = Join-Path $PSScriptRoot 'templates'
$resolvedTargetPath = (Resolve-Path -LiteralPath $TargetPath -ErrorAction SilentlyContinue)
if ($resolvedTargetPath) { $TargetPath = $resolvedTargetPath.Path }

switch ($PSCmdlet.ParameterSetName) {
    'Uninstall' {
        Invoke-ProjectUninstall -TargetPath $TargetPath
    }
    default {
        try {
            Invoke-ProjectInstall -TargetPath $TargetPath -TemplateDir $templateDir -Template $Template `
                -SkipGitignore:$SkipGitignore -Force:$Force
        }
        catch {
            Write-Host "`n❌ $($_.Exception.Message)`n" -ForegroundColor Red
            throw
        }
    }
}
