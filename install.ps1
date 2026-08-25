#Requires -Version 7.0
<#
.SYNOPSIS
    Transactionally symlinks Copilot CLI global config from this repo into a
    Copilot home directory (default ~/.copilot/), with recovery-aware
    install, status, repair, and uninstall modes.

.DESCRIPTION
    Creates symbolic links for copilot-instructions.md, instructions/,
    agents/, and skills/ from this repository into the target Copilot home.
    Optionally also installs mcp-config.json for MCP server configuration.

    Every mutating run is preflighted (source availability, mergeable JSON
    validity, symlink capability), backs up any pre-existing conflicting
    item under a uniquely timestamped folder before it is touched, and
    records what it did in an install manifest under the target
    (<target>\.np-copilot-installer\). If any step fails, only the
    artifacts created by that invocation are removed and any items backed
    up during the same run are restored — the target is left exactly as it
    was found.

    MCP configuration merges preserve user-owned server entries. Entries
    this repo owns are tracked by content hash in the manifest: unchanged
    owned entries are updated on re-install, user-modified owned entries
    are preserved and flagged as a conflict (never silently overwritten).

    Modes -Mcp, -Uninstall, -Status, and -Repair are mutually exclusive.
    -TargetRoot exists so automated tests can point the installer at an
    isolated temporary directory instead of the real Copilot home; it
    should not normally be passed by hand.

.PARAMETER TargetRoot
    Copilot home directory to install into. Defaults to ~/.copilot. Intended
    for test isolation — production use should rely on the default.

.PARAMETER Mcp
    Also installs mcp-config.json for MCP server configuration (SearXNG
    search, Playwright browser). Only valid for the default install mode.

    If no mcp-config.json exists at the target, it is symlinked. If a
    regular (non-symlink) file already exists there, this repo's servers
    are merged into it: user-owned entries are always preserved, and
    entries owned by this repo are added or refreshed without disturbing
    entries you have customized yourself.

.PARAMETER Uninstall
    Removes only the artifacts recorded in this installer's manifest, and
    restores any items that were backed up when they were installed. Items
    that were modified since install are left in place with recovery
    guidance printed instead of being deleted.

.PARAMETER Status
    Reports installation health (ok / missing / drifted / conflict) and
    backup history without ever printing MCP configuration bodies,
    endpoints, or secrets.

.PARAMETER Repair
    Re-applies only the artifacts recorded in the manifest that are
    currently missing or drifted from their expected state. Artifacts that
    already match are left untouched. Requires a prior successful install.

.EXAMPLE
    .\install.ps1
    Installs core config (instructions, agents, skills).

.EXAMPLE
    .\install.ps1 -Mcp
    Installs core config plus MCP server configuration.

.EXAMPLE
    .\install.ps1 -WhatIf
    Shows what an install would do without changing anything.

.EXAMPLE
    .\install.ps1 -Status
    Reports current installation health without secrets.

.EXAMPLE
    .\install.ps1 -Repair
    Fixes any missing or drifted artifacts from a previous install.

.EXAMPLE
    .\install.ps1 -Uninstall
    Removes installed artifacts and restores anything they replaced.

.EXAMPLE
    .\install.ps1 -TargetRoot 'C:\temp\fake-copilot-home' -Mcp
    Installs into an isolated directory instead of the real Copilot home.
    Used by tests; not intended for interactive use.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Install')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Uninstall',
    Justification = 'Used as a parameter-set discriminator via $PSCmdlet.ParameterSetName, not read directly.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Status',
    Justification = 'Used as a parameter-set discriminator via $PSCmdlet.ParameterSetName, not read directly.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Repair',
    Justification = 'Used as a parameter-set discriminator via $PSCmdlet.ParameterSetName, not read directly.')]
param(
    [Parameter()]
    [string]$TargetRoot = (Join-Path $HOME '.copilot'),

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Mcp,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'Status', Mandatory)]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Repair', Mandatory)]
    [switch]$Repair
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Write-Status {
    param([Parameter(Mandatory)][string]$Icon, [Parameter(Mandatory)][string]$Message)
    Write-Host "  $Icon $Message"
}

function Resolve-LinkTarget {
    <#
    .SYNOPSIS
        Returns the fully-qualified target path of a symbolic link item, or
        $null if the item is not a symbolic link.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

    if ($Item.LinkType -ne 'SymbolicLink' -or -not $Item.Target) {
        return $null
    }

    $rawTarget = @($Item.Target)[0]
    if ([System.IO.Path]::IsPathRooted($rawTarget)) {
        return [System.IO.Path]::GetFullPath($rawTarget)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Item.DirectoryName $rawTarget))
}

function Test-PathIsUnderRoot {
    <#
    .SYNOPSIS
        Returns $true if Path is Root itself, or nested under it.
    .DESCRIPTION
        Used to classify a symlink this installer (or an earlier version of
        it) is likely to have created itself — one whose target resolves
        somewhere under this repo's SourceRoot — versus a foreign symlink a
        user created pointing anywhere else, which must never be silently
        deleted.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $sep = [System.IO.Path]::DirectorySeparatorChar
    $altSep = [System.IO.Path]::AltDirectorySeparatorChar
    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($sep, $altSep)
    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep, $altSep)

    if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $normalizedPath.StartsWith($normalizedRoot + $sep, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-SymlinkCapability {
    <#
    .SYNOPSIS
        Probes whether this process can create symbolic links, using a
        throwaway path under the system temp directory. Never touches the
        install target and always cleans up after itself.
    .NOTES
        This probe must run for real even during -WhatIf — it is the only
        way to know whether a mutating run would succeed, and it is fully
        self-contained and self-cleaning outside TargetRoot. The local
        $WhatIfPreference override below prevents the ambient -WhatIf from
        turning New-Item into a silent no-op that would report a false
        capability positive.
    #>
    $WhatIfPreference = $false
    $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) "np-copilot-install-probe-$([guid]::NewGuid())"
    $probeTarget = Join-Path $probeDir 'target.tmp'
    $probeLink = Join-Path $probeDir 'link.tmp'
    try {
        New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
        Set-Content -LiteralPath $probeTarget -Value 'probe' -Encoding utf8
        New-Item -ItemType SymbolicLink -Path $probeLink -Target $probeTarget -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-JsonFile {
    <#
    .SYNOPSIS
        Returns $true if the given path contains parseable, non-empty JSON.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
        $raw | ConvertFrom-Json -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Serializes a value to JSON with object keys sorted, so semantically
        identical values always hash the same regardless of key order.
    #>
    param($InputObject)

    if ($null -eq $InputObject) { return 'null' }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $parts = foreach ($p in ($InputObject.PSObject.Properties | Sort-Object Name)) {
            '"{0}":{1}' -f $p.Name, (ConvertTo-CanonicalJson $p.Value)
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $parts = foreach ($k in ($InputObject.Keys | Sort-Object)) {
            '"{0}":{1}' -f $k, (ConvertTo-CanonicalJson $InputObject[$k])
        }
        return '{' + ($parts -join ',') + '}'
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $parts = foreach ($item in $InputObject) { ConvertTo-CanonicalJson $item }
        return '[' + ($parts -join ',') + ']'
    }
    if ($InputObject -is [bool]) { return $(if ($InputObject) { 'true' } else { 'false' }) }
    return (ConvertTo-Json -InputObject $InputObject -Compress -Depth 10)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Get-EntryHash {
    param($Value)
    Get-Sha256Hex -Text (ConvertTo-CanonicalJson $Value)
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

function Import-InstallManifest {
    param([Parameter(Mandatory)][string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    try {
        return Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Status '⚠️' "Manifest at $ManifestPath is corrupt and will be treated as absent: $($_.Exception.Message)"
        return $null
    }
}

function New-ManifestObject {
    <#
    .SYNOPSIS
        Builds the manifest to persist after a run, preserving any prior
        artifact records this run did not touch (e.g. a previously
        installed MCP artifact when re-running install.ps1 without -Mcp).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only; performs no I/O or state mutation. Save-Manifest is the ShouldProcess-gated write.')]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$RunArtifacts,
        $ExistingManifest
    )

    $nowIso = (Get-Date).ToUniversalTime().ToString('o')
    $createdAt = if ($ExistingManifest) { $ExistingManifest.CreatedAt } else { $nowIso }

    $processedNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($RunArtifacts.Name), [System.StringComparer]::Ordinal)

    $preserved = @()
    if ($ExistingManifest) {
        foreach ($prev in @($ExistingManifest.Artifacts)) {
            if (-not $processedNames.Contains($prev.Name)) { $preserved += $prev }
        }
    }

    $artifactRecords = foreach ($a in $RunArtifacts) {
        [ordered]@{
            Name         = $a.Name
            Kind         = $a.Kind
            TargetPath   = $a.TargetPath
            SourcePath   = $a.SourcePath
            BackupPath   = $a.BackupPath
            OwnedEntries = $a.OwnedEntries
            EntryStatus  = $a.EntryStatus
        }
    }
    $artifactRecords = @($artifactRecords) + @($preserved)

    $mcpInstalled = ($artifactRecords | Where-Object { $_.Name -eq 'mcp-config.json' }).Count -gt 0

    [ordered]@{
        SchemaVersion = 1
        SourceRoot    = $SourceRoot
        TargetRoot    = $TargetRoot
        CreatedAt     = $createdAt
        UpdatedAt     = $nowIso
        McpInstalled  = $mcpInstalled
        Artifacts     = $artifactRecords
    }
}

function Save-Manifest {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    if ($PSCmdlet.ShouldProcess($ManifestPath, 'Write install manifest')) {
        $dir = Split-Path $ManifestPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($Manifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $ManifestPath -Encoding utf8 -NoNewline
    }
}

# ---------------------------------------------------------------------------
# Transaction log / rollback
# ---------------------------------------------------------------------------

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
                'CreatedSymlink' {
                    if (Test-Path -LiteralPath $entry.Path) {
                        (Get-Item -LiteralPath $entry.Path -Force).Delete()
                    }
                }
                'CreatedDirectory' {
                    Remove-Item -LiteralPath $entry.Path -Force -Recurse -ErrorAction SilentlyContinue
                }
                'RemovedStaleLink' {
                    # The stale link pointed elsewhere and carried no user data; nothing to restore.
                }
                'MovedToBackup' {
                    if (Test-Path -LiteralPath $entry.Path) {
                        Remove-Item -LiteralPath $entry.Path -Force -Recurse -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $entry.BackupPath -Destination $entry.Path -Force
                }
                'WroteFile' {
                    if ($entry.PreviousContentPath -and (Test-Path -LiteralPath $entry.PreviousContentPath)) {
                        Copy-Item -LiteralPath $entry.PreviousContentPath -Destination $entry.Path -Force
                    }
                    else {
                        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Write-Status '↩️' "Reverted $($entry.Action): $($entry.Path)"
        }
        catch {
            Write-Status '❌' "Rollback step failed for $($entry.Path): $($_.Exception.Message)"
        }
    }

    # A partially-completed backup (e.g. New-ArtifactBackup created the timestamped
    # run folder but the subsequent Move-Item failed partway, leaving only empty
    # directory husks behind) can leave stray empty folders. Clean them up so
    # failed runs never leave stray artifacts; never touch a folder that still
    # holds actual file content, since that could be genuine backed-up data.
    if ($script:RunBackupDir -and (Test-Path -LiteralPath $script:RunBackupDir)) {
        $leftoverFiles = Get-ChildItem -LiteralPath $script:RunBackupDir -Force -Recurse -File -ErrorAction SilentlyContinue
        if (-not $leftoverFiles) {
            Remove-Item -LiteralPath $script:RunBackupDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

function Test-InstallPreflight {
    <#
    .SYNOPSIS
        Validates every source path, mergeable JSON file, and symlink
        capability before any mutation happens. Throws with an aggregated
        report if anything would prevent a safe install.
    #>
    param(
        [Parameter(Mandatory)][array]$Links,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    Write-Host "`n🔍 Preflight checks..." -ForegroundColor Cyan
    $problems = [System.Collections.Generic.List[string]]::new()

    foreach ($link in $Links) {
        $sourcePath = Join-Path $SourceRoot $link.Name
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            $problems.Add("Source not found: $sourcePath")
            continue
        }

        if ($link.Mergeable) {
            if (-not (Test-JsonFile -Path $sourcePath)) {
                $problems.Add("Source is not valid JSON: $sourcePath")
            }

            $targetPath = Join-Path $TargetRoot $link.Name
            if (Test-Path -LiteralPath $targetPath) {
                $existing = Get-Item -LiteralPath $targetPath -Force
                if ($existing.LinkType -ne 'SymbolicLink' -and -not (Test-JsonFile -Path $targetPath)) {
                    $problems.Add("Existing target is not valid JSON and cannot be merged: $targetPath")
                }
            }
        }
    }

    if (-not (Test-SymlinkCapability)) {
        $problems.Add('Symbolic link creation is not permitted for this process. Enable Developer Mode or run elevated.')
    }

    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-Status '❌' $p }
        throw "Preflight failed with $($problems.Count) problem(s). No changes were made."
    }

    Write-Status '✅' 'Preflight checks passed.'
}

# ---------------------------------------------------------------------------
# Core (non-MCP) link install
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
        Move-Item -LiteralPath $Path -Destination $destination -Force
        $script:TxLog.Add(@{ Action = 'MovedToBackup'; Path = $Path; BackupPath = $destination })
        Write-Status '📦' "Backed up existing item to: $destination"
    }

    return $destination
}

function Install-CoreLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][hashtable]$Link,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$BackupDir,
        $PreviousArtifact
    )

    $sourcePath = Join-Path $SourceRoot $Link.Name
    $targetPath = Join-Path $TargetRoot $Link.Name
    # Carry forward the last known backup unless this run creates a fresh one below —
    # an idempotent no-op run must never forget a recovery point recorded earlier.
    $backupPath = if ($PreviousArtifact) { $PreviousArtifact.BackupPath } else { $null }

    if (Test-Path -LiteralPath $targetPath) {
        $existing = Get-Item -LiteralPath $targetPath -Force

        if (($existing.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $existing) -eq $sourcePath)) {
            Write-Status '✅' "$($Link.Name) already linked."
            return [pscustomobject]@{
                Name = $Link.Name; Kind = 'CoreLink'; TargetPath = $targetPath
                SourcePath = $sourcePath; BackupPath = $backupPath; OwnedEntries = @{}; EntryStatus = @{}
            }
        }

        if ($existing.LinkType -eq 'SymbolicLink') {
            $existingTarget = Resolve-LinkTarget $existing
            if ($existingTarget -and (Test-PathIsUnderRoot -Path $existingTarget -Root $SourceRoot)) {
                # Points somewhere else under this same repo (e.g. an older
                # artifact name/location from a previous run/version of this
                # installer): known to be ours, safe to replace without a backup.
                if ($PSCmdlet.ShouldProcess($targetPath, 'Remove stale symlink')) {
                    $existing.Delete()
                    $script:TxLog.Add(@{ Action = 'RemovedStaleLink'; Path = $targetPath })
                }
            }
            else {
                # A foreign symlink this installer never created (points outside
                # this repo, or is unresolvable/dangling): preserve and restore it
                # exactly as found, the same as any other pre-existing item.
                $backupPath = New-ArtifactBackup -Path $targetPath -BackupDir $BackupDir
            }
        }
        else {
            $backupPath = New-ArtifactBackup -Path $targetPath -BackupDir $BackupDir
        }
    }

    if ($PSCmdlet.ShouldProcess($targetPath, "Create symlink -> $sourcePath")) {
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
        $script:TxLog.Add(@{ Action = 'CreatedSymlink'; Path = $targetPath })
        Write-Status '✅' "$($Link.Name) -> $sourcePath"
    }

    [pscustomobject]@{
        Name = $Link.Name; Kind = 'CoreLink'; TargetPath = $targetPath
        SourcePath = $sourcePath; BackupPath = $backupPath; OwnedEntries = @{}; EntryStatus = @{}
    }
}

# ---------------------------------------------------------------------------
# MCP install / merge
# ---------------------------------------------------------------------------

function Sync-McpEntries {
    <#
    .SYNOPSIS
        Reconciles this repo's mcpServers entries into the target's
        mcpServers object (mutated in place), classifying each source entry
        as Added, Updated (unchanged owned entry refreshed), Preserved
        (already matches source), or Conflict (owned entry the user
        changed, or a same-named entry we have never owned — never
        overwritten).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Operates on a whole collection of MCP server entries as a batch; a singular name would misrepresent its contract.')]
    param(
        [Parameter(Mandatory)]$SourceServers,
        [Parameter(Mandatory)]$TargetServersRef,
        [Parameter(Mandatory)][hashtable]$PreviousOwnedHashes
    )

    $added = [System.Collections.Generic.List[string]]::new()
    $updated = [System.Collections.Generic.List[string]]::new()
    $preserved = [System.Collections.Generic.List[string]]::new()
    $conflicts = [System.Collections.Generic.List[string]]::new()
    $ownedHashes = @{}

    foreach ($prop in $SourceServers.PSObject.Properties) {
        $entryName = $prop.Name
        $sourceValue = $prop.Value
        $sourceHash = Get-EntryHash $sourceValue
        $existingProp = $TargetServersRef.PSObject.Properties[$entryName]

        if (-not $existingProp) {
            $TargetServersRef | Add-Member -NotePropertyName $entryName -NotePropertyValue $sourceValue -Force
            $added.Add($entryName)
            $ownedHashes[$entryName] = $sourceHash
            continue
        }

        $currentHash = Get-EntryHash $existingProp.Value
        if ($currentHash -eq $sourceHash) {
            $preserved.Add($entryName)
            $ownedHashes[$entryName] = $sourceHash
            continue
        }

        $previousHash = $PreviousOwnedHashes[$entryName]
        if ($previousHash -and ($previousHash -eq $currentHash)) {
            # Unchanged since our last install of this entry: safe to refresh.
            $existingProp.Value = $sourceValue
            $updated.Add($entryName)
            $ownedHashes[$entryName] = $sourceHash
            continue
        }

        # Either never owned by us, or the user modified an owned entry since our last install.
        $conflicts.Add($entryName)
        if ($previousHash) { $ownedHashes[$entryName] = $previousHash }
    }

    [pscustomobject]@{
        Added = @($added); Updated = @($updated); Preserved = @($preserved); Conflicts = @($conflicts)
        OwnedHashes = $ownedHashes
    }
}

function Install-McpMergedConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][hashtable]$PreviousOwnedHashes,
        $PreviousArtifact
    )

    # Carry forward the last known backup unless this run creates a fresh one below —
    # a merge round with no changes must never forget a recovery point recorded earlier.
    $carriedBackupPath = if ($PreviousArtifact) { $PreviousArtifact.BackupPath } else { $null }

    $sourceJson = Get-Content -LiteralPath $SourcePath -Raw -Encoding utf8 | ConvertFrom-Json
    $targetJson = Get-Content -LiteralPath $TargetPath -Raw -Encoding utf8 | ConvertFrom-Json

    if ($null -eq $targetJson.mcpServers) {
        $targetJson | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $sourceJson.mcpServers) {
        Write-Status '⚠️' 'Source has no mcpServers — nothing to merge.'
        return [pscustomobject]@{
            Name = 'mcp-config.json'; Kind = 'McpMerge'; TargetPath = $TargetPath; SourcePath = $SourcePath
            BackupPath = $carriedBackupPath; OwnedEntries = @{}; EntryStatus = @{}
        }
    }

    $sync = Sync-McpEntries -SourceServers $sourceJson.mcpServers -TargetServersRef $targetJson.mcpServers -PreviousOwnedHashes $PreviousOwnedHashes

    # The manifest's restore point for this artifact must always be the
    # pristine, pre-install copy of the target file — never a snapshot taken
    # during a later re-merge, which would already contain repo-owned
    # entries and would reintroduce them on uninstall/rollback (the target
    # would no longer be restored to what the user actually started with).
    # Only the very first backup ever taken for this artifact is allowed to
    # become that restore point; it is carried forward untouched on every
    # subsequent re-merge. Each re-merge still takes its own throwaway
    # backup purely so *this run's* Undo-Transaction can recover from a
    # failed write.
    $hasPristineBackup = $carriedBackupPath -and (Test-Path -LiteralPath $carriedBackupPath)
    $manifestBackupPath = $carriedBackupPath

    if (($sync.Added.Count -gt 0) -or ($sync.Updated.Count -gt 0)) {
        $runBackupPath = Join-Path $BackupDir (Split-Path $TargetPath -Leaf)
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Back up before MCP merge')) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            Copy-Item -LiteralPath $TargetPath -Destination $runBackupPath -Force
            Write-Status '📦' "Backed up existing MCP config to: $runBackupPath"
        }

        if (-not $hasPristineBackup) {
            # First backup ever taken for this artifact: the target is still
            # in its pre-install state, so this copy IS the pristine
            # restore point going forward.
            $manifestBackupPath = $runBackupPath
        }

        if ($PSCmdlet.ShouldProcess($TargetPath, 'Write merged MCP configuration')) {
            # Register rollback intent BEFORE mutating the file, so a
            # partial/failed Set-Content is still recoverable by
            # Undo-Transaction.
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $runBackupPath })
            ($targetJson | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $TargetPath -Encoding utf8 -NoNewline
            Write-Status '🔀' "Merged MCP config written to: $TargetPath"
        }
    }

    if ($sync.Added.Count -gt 0) { Write-Status '➕' "Added MCP servers: $($sync.Added -join ', ')" }
    if ($sync.Updated.Count -gt 0) { Write-Status '🔄' "Refreshed unchanged owned MCP servers: $($sync.Updated -join ', ')" }
    if ($sync.Conflicts.Count -gt 0) {
        Write-Status '⚠️' "Preserved MCP servers with a conflict (user-modified or not repo-owned): $($sync.Conflicts -join ', ')"
    }
    if (($sync.Added.Count -eq 0) -and ($sync.Updated.Count -eq 0) -and ($sync.Conflicts.Count -eq 0)) {
        Write-Status '✅' 'mcp-config.json already up to date.'
    }

    $entryStatus = @{}
    foreach ($n in $sync.Added) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Updated) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Preserved) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Conflicts) { $entryStatus[$n] = 'Conflict' }

    [pscustomobject]@{
        Name = 'mcp-config.json'; Kind = 'McpMerge'; TargetPath = $TargetPath; SourcePath = $SourcePath
        BackupPath = $manifestBackupPath; OwnedEntries = $sync.OwnedHashes; EntryStatus = $entryStatus
    }
}

function Install-McpArtifact {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][hashtable]$PreviousOwnedHashes,
        $PreviousArtifact
    )

    # Carry forward the last known backup unless this run creates a fresh one below —
    # an idempotent no-op run must never forget a recovery point recorded earlier.
    $backupPath = if ($PreviousArtifact) { $PreviousArtifact.BackupPath } else { $null }

    if (Test-Path -LiteralPath $TargetPath) {
        $existing = Get-Item -LiteralPath $TargetPath -Force

        if ($existing.LinkType -eq 'SymbolicLink') {
            if ((Resolve-LinkTarget $existing) -eq $SourcePath) {
                Write-Status '✅' 'mcp-config.json already linked.'
                return [pscustomobject]@{
                    Name = 'mcp-config.json'; Kind = 'McpLink'; TargetPath = $TargetPath; SourcePath = $SourcePath
                    BackupPath = $backupPath; OwnedEntries = @{}; EntryStatus = @{}
                }
            }

            $existingTarget = Resolve-LinkTarget $existing
            if ($existingTarget -and (Test-PathIsUnderRoot -Path $existingTarget -Root $SourceRoot)) {
                # Points somewhere else under this same repo: known to be
                # ours (an earlier run/version of this installer), safe to
                # replace without a backup.
                if ($PSCmdlet.ShouldProcess($TargetPath, 'Remove stale MCP symlink')) {
                    $existing.Delete()
                    $script:TxLog.Add(@{ Action = 'RemovedStaleLink'; Path = $TargetPath })
                }
            }
            else {
                # A foreign symlink this installer never created (points
                # outside this repo, or is unresolvable/dangling): preserve
                # and restore it exactly as found, the same as any other
                # pre-existing item.
                $backupPath = New-ArtifactBackup -Path $TargetPath -BackupDir $BackupDir
            }
        }
        else {
            return Install-McpMergedConfig -SourcePath $SourcePath -TargetPath $TargetPath -BackupDir $BackupDir `
                -PreviousOwnedHashes $PreviousOwnedHashes -PreviousArtifact $PreviousArtifact
        }
    }

    # No pre-existing user config (or a stale/foreign link was just removed/backed up): safe to symlink directly.
    if ($PSCmdlet.ShouldProcess($TargetPath, "Create symlink -> $SourcePath")) {
        New-Item -ItemType SymbolicLink -Path $TargetPath -Target $SourcePath | Out-Null
        $script:TxLog.Add(@{ Action = 'CreatedSymlink'; Path = $TargetPath })
        Write-Status '✅' "mcp-config.json -> $SourcePath"
    }

    [pscustomobject]@{
        Name = 'mcp-config.json'; Kind = 'McpLink'; TargetPath = $TargetPath; SourcePath = $SourcePath
        BackupPath = $backupPath; OwnedEntries = @{}; EntryStatus = @{}
    }
}

# ---------------------------------------------------------------------------
# Install / Repair orchestration (shared transaction logic)
# ---------------------------------------------------------------------------

function Invoke-InstallOrRepair {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][array]$Links,
        [Parameter(Mandatory)][string]$InstallerDir,
        [Parameter(Mandatory)][string]$ManifestPath,
        $ExistingManifest,
        [Parameter(Mandatory)][bool]$IsRepair
    )

    $verb = if ($IsRepair) { 'Repairing' } else { 'Installing' }
    Write-Host "`n🔗 $verb Copilot global config..." -ForegroundColor Cyan
    Write-Host "   Source: $SourceRoot"
    Write-Host "   Target: $TargetRoot"

    Test-InstallPreflight -Links $Links -SourceRoot $SourceRoot -TargetRoot $TargetRoot

    $script:TxLog = [System.Collections.Generic.List[object]]::new()
    $backupDir = Join-Path $InstallerDir "backups\$script:RunStamp"
    $script:RunBackupDir = $backupDir

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        if ($PSCmdlet.ShouldProcess($TargetRoot, 'Create target directory')) {
            New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
            $script:TxLog.Add(@{ Action = 'CreatedDirectory'; Path = $TargetRoot })
        }
    }

    $artifacts = @()
    try {
        foreach ($link in $Links) {
            $prevArtifact = $null
            if ($ExistingManifest) {
                $prevArtifact = @($ExistingManifest.Artifacts) | Where-Object { $_.Name -eq $link.Name } | Select-Object -First 1
            }

            if ($link.Mergeable) {
                $prevHashes = @{}
                if ($prevArtifact -and $prevArtifact.OwnedEntries) {
                    foreach ($p in $prevArtifact.OwnedEntries.PSObject.Properties) { $prevHashes[$p.Name] = $p.Value }
                }
                $sourcePath = Join-Path $SourceRoot $link.Name
                $targetPath = Join-Path $TargetRoot $link.Name
                $artifact = Install-McpArtifact -SourcePath $sourcePath -SourceRoot $SourceRoot -TargetPath $targetPath -BackupDir $backupDir `
                    -PreviousOwnedHashes $prevHashes -PreviousArtifact $prevArtifact
            }
            else {
                $artifact = Install-CoreLink -Link $link -SourceRoot $SourceRoot -TargetRoot $TargetRoot -BackupDir $backupDir `
                    -PreviousArtifact $prevArtifact
            }
            $artifacts += $artifact
        }
    }
    catch {
        Write-Status '❌' "$verb step failed: $($_.Exception.Message)"
        Undo-Transaction
        throw
    }

    if ($WhatIfPreference) {
        Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
        return
    }

    $manifest = New-ManifestObject -SourceRoot $SourceRoot -TargetRoot $TargetRoot -RunArtifacts $artifacts -ExistingManifest $ExistingManifest
    Save-Manifest -Manifest $manifest -ManifestPath $ManifestPath

    Write-Host "`n✅ $verb complete.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

function Invoke-StatusReport {
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$InstallerDir
    )

    Write-Host "`n📋 Copilot global config status" -ForegroundColor Cyan
    Write-Host "   Target: $TargetRoot`n"

    $manifest = Import-InstallManifest -ManifestPath $ManifestPath
    if (-not $manifest) {
        Write-Status 'ℹ️' 'No installation manifest found. Run install.ps1 to install.'
        return
    }

    Write-Status 'ℹ️' "Installed: $($manifest.CreatedAt)  |  Last updated: $($manifest.UpdatedAt)"
    Write-Status 'ℹ️' "MCP tracked: $($manifest.McpInstalled)"
    Write-Host ''

    foreach ($artifact in @($manifest.Artifacts)) {
        $targetPath = $artifact.TargetPath
        $health = 'Missing'
        $icon = '❌'

        if (Test-Path -LiteralPath $targetPath) {
            $item = Get-Item -LiteralPath $targetPath -Force
            if ($artifact.Kind -in @('CoreLink', 'McpLink')) {
                if (($item.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $item) -eq $artifact.SourcePath)) {
                    $health = 'OK'; $icon = '✅'
                }
                else {
                    $health = 'Drifted (not the expected symlink)'; $icon = '⚠️'
                }
            }
            elseif ($artifact.Kind -eq 'McpMerge') {
                $conflictCount = @($artifact.EntryStatus.PSObject.Properties | Where-Object { $_.Value -eq 'Conflict' }).Count
                if ($conflictCount -gt 0) {
                    $health = "Managed (merged file) — $conflictCount conflict(s)"; $icon = '⚠️'
                }
                else {
                    $health = 'Managed (merged file)'; $icon = '✅'
                }
            }
        }

        Write-Status $icon "$($artifact.Name): $health"

        if ($artifact.Kind -eq 'McpMerge' -and $artifact.EntryStatus) {
            foreach ($p in $artifact.EntryStatus.PSObject.Properties) {
                $entryIcon = if ($p.Value -eq 'Conflict') { '⚠️' } else { '•' }
                Write-Status "  $entryIcon" "$($p.Name): $($p.Value)"
            }
        }
    }

    $backupsDir = Join-Path $InstallerDir 'backups'
    Write-Host ''
    if (Test-Path -LiteralPath $backupsDir) {
        $runs = @(Get-ChildItem -LiteralPath $backupsDir -Directory | Sort-Object Name)
        Write-Status 'ℹ️' "Backup snapshots retained: $($runs.Count)"
        foreach ($r in $runs) { Write-Status '  •' $r.Name }
    }
    else {
        Write-Status 'ℹ️' 'Backup snapshots retained: 0'
    }
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

function Remove-OwnedMcpEntries {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Removes a whole collection of owned MCP server entries as a batch; a singular name would misrepresent its contract.')]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)]$Artifact
    )

    $conflicts = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()

    try {
        $json = Get-Content -LiteralPath $TargetPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Status '❌' "Cannot parse $TargetPath during uninstall: $($_.Exception.Message)"
        $names = @()
        if ($Artifact.EntryStatus) { $names = @($Artifact.EntryStatus.PSObject.Properties.Name) }
        return [pscustomobject]@{ Conflicts = $names; RemainingCount = -1 }
    }

    if ($null -eq $json.mcpServers) {
        return [pscustomobject]@{ Conflicts = @(); RemainingCount = 0 }
    }

    $owned = @{}
    if ($Artifact.OwnedEntries) {
        foreach ($p in $Artifact.OwnedEntries.PSObject.Properties) { $owned[$p.Name] = $p.Value }
    }

    foreach ($name in $owned.Keys) {
        $prop = $json.mcpServers.PSObject.Properties[$name]
        if (-not $prop) { continue }
        $currentHash = Get-EntryHash $prop.Value
        if ($currentHash -eq $owned[$name]) {
            $json.mcpServers.PSObject.Properties.Remove($name)
            $removed.Add($name)
        }
        else {
            $conflicts.Add($name)
        }
    }

    if ($removed.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Remove unmodified repo-owned MCP entries')) {
            ($json | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $TargetPath -Encoding utf8 -NoNewline
        }
        Write-Status '➖' "Removed managed MCP servers: $($removed -join ', ')"
    }

    $remainingCount = @($json.mcpServers.PSObject.Properties).Count
    [pscustomobject]@{ Conflicts = @($conflicts); RemainingCount = $remainingCount }
}

function Invoke-LegacyUninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    Write-Status 'ℹ️' 'No installer manifest found; checking for unmanaged symlinks from an earlier installer version.'
    $legacyNames = @('copilot-instructions.md', 'instructions', 'agents', 'skills', 'mcp-config.json')
    $found = $false

    foreach ($name in $legacyNames) {
        $targetPath = Join-Path $TargetRoot $name
        $sourcePath = Join-Path $SourceRoot $name
        if (-not (Test-Path -LiteralPath $targetPath)) { continue }

        $item = Get-Item -LiteralPath $targetPath -Force
        if (($item.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $item) -eq $sourcePath)) {
            $found = $true
            if ($PSCmdlet.ShouldProcess($targetPath, 'Remove legacy symlink')) {
                $item.Delete()
                Write-Status '✅' "Removed legacy symlink: $targetPath"
            }
        }
    }

    if (-not $found) {
        Write-Status '⏭️' 'Nothing to uninstall.'
    }
}

function Invoke-UninstallFlow {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$InstallerDir,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    Write-Host "`n🗑️  Uninstalling Copilot global config..." -ForegroundColor Yellow

    $manifest = Import-InstallManifest -ManifestPath $ManifestPath
    if (-not $manifest) {
        Invoke-LegacyUninstall -TargetRoot $TargetRoot -SourceRoot $SourceRoot
        return
    }

    $remainingArtifacts = [System.Collections.Generic.List[object]]::new()
    $anyConflict = $false

    foreach ($artifact in @($manifest.Artifacts)) {
        $targetPath = $artifact.TargetPath

        if ($artifact.Kind -in @('CoreLink', 'McpLink')) {
            if (-not (Test-Path -LiteralPath $targetPath)) {
                Write-Status '⏭️' "$($artifact.Name): already absent."
                if ($artifact.BackupPath -and (Test-Path -LiteralPath $artifact.BackupPath)) {
                    if ($PSCmdlet.ShouldProcess($targetPath, 'Restore backed-up item')) {
                        Move-Item -LiteralPath $artifact.BackupPath -Destination $targetPath -Force
                        Write-Status '♻️' "Restored previous item to $targetPath"
                    }
                }
                continue
            }

            $item = Get-Item -LiteralPath $targetPath -Force
            if (($item.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $item) -eq $artifact.SourcePath)) {
                if ($PSCmdlet.ShouldProcess($targetPath, 'Remove managed symlink')) {
                    $item.Delete()
                    Write-Status '✅' "Removed: $targetPath"
                    if ($artifact.BackupPath -and (Test-Path -LiteralPath $artifact.BackupPath)) {
                        Move-Item -LiteralPath $artifact.BackupPath -Destination $targetPath -Force
                        Write-Status '♻️' "Restored previous item to $targetPath"
                    }
                }
            }
            else {
                $anyConflict = $true
                $remainingArtifacts.Add($artifact)
                Write-Status '⚠️' "$($artifact.Name) changed since install; left in place at $targetPath."
                Write-Host "     Recovery: compare it with $($artifact.SourcePath); remove it manually and re-run -Uninstall to finish, or run -Repair to relink." -ForegroundColor Yellow
            }
        }
        elseif ($artifact.Kind -eq 'McpMerge') {
            if (-not (Test-Path -LiteralPath $targetPath)) {
                Write-Status '⏭️' "$($artifact.Name): already absent."
                continue
            }

            $result = Remove-OwnedMcpEntries -TargetPath $targetPath -Artifact $artifact
            if ($result.RemainingCount -lt 0 -or $result.Conflicts.Count -gt 0) {
                $anyConflict = $true
                $remainingArtifacts.Add($artifact)
                if ($result.Conflicts.Count -gt 0) {
                    Write-Status '⚠️' "mcp-config.json retains user-modified entries: $($result.Conflicts -join ', ')."
                    Write-Host "     Recovery: these were left untouched; edit $targetPath by hand if you no longer want them." -ForegroundColor Yellow
                }
                else {
                    Write-Host "     Recovery: fix the JSON in $targetPath by hand, then re-run -Uninstall." -ForegroundColor Yellow
                }
            }
            elseif ($result.RemainingCount -eq 0 -and $artifact.BackupPath -and (Test-Path -LiteralPath $artifact.BackupPath)) {
                if ($PSCmdlet.ShouldProcess($targetPath, 'Restore pre-install MCP configuration')) {
                    Remove-Item -LiteralPath $targetPath -Force
                    Move-Item -LiteralPath $artifact.BackupPath -Destination $targetPath -Force
                    Write-Status '♻️' "Restored original mcp-config.json to $targetPath"
                }
            }
        }
    }

    if (-not $anyConflict) {
        if ($PSCmdlet.ShouldProcess($InstallerDir, 'Remove installer state')) {
            Remove-Item -LiteralPath $InstallerDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "`n✅ Uninstall complete. Installer state removed.`n" -ForegroundColor Green
    }
    else {
        $manifest.Artifacts = @($remainingArtifacts)
        $manifest.UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Save-Manifest -Manifest $manifest -ManifestPath $ManifestPath
        Write-Host "`nℹ️  Some items needed manual attention (see guidance above). Re-run -Uninstall after resolving them to finish cleanup.`n" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$source = $PSScriptRoot
$target = $TargetRoot
$installerDir = Join-Path $target '.np-copilot-installer'
$manifestPath = Join-Path $installerDir 'manifest.json'
$script:RunStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')

$coreLinks = @(
    @{ Name = 'copilot-instructions.md'; Type = 'File' }
    @{ Name = 'instructions'; Type = 'Directory' }
    @{ Name = 'agents'; Type = 'Directory' }
    @{ Name = 'skills'; Type = 'Directory' }
)
$mcpLink = @{ Name = 'mcp-config.json'; Type = 'File'; Mergeable = $true }

switch ($PSCmdlet.ParameterSetName) {
    'Status' {
        Invoke-StatusReport -TargetRoot $target -ManifestPath $manifestPath -InstallerDir $installerDir
    }
    'Uninstall' {
        Invoke-UninstallFlow -TargetRoot $target -ManifestPath $manifestPath -InstallerDir $installerDir -SourceRoot $source
    }
    'Repair' {
        $existingManifest = Import-InstallManifest -ManifestPath $manifestPath
        if (-not $existingManifest) {
            throw "No installation manifest found at $manifestPath. Run install.ps1 first, then use -Repair."
        }
        $links = @($coreLinks)
        if ($existingManifest.McpInstalled) { $links += $mcpLink }
        Invoke-InstallOrRepair -SourceRoot $source -TargetRoot $target -Links $links -InstallerDir $installerDir `
            -ManifestPath $manifestPath -ExistingManifest $existingManifest -IsRepair $true
    }
    default {
        $existingManifest = Import-InstallManifest -ManifestPath $manifestPath
        $links = @($coreLinks)
        if ($Mcp) { $links += $mcpLink }
        Invoke-InstallOrRepair -SourceRoot $source -TargetRoot $target -Links $links -InstallerDir $installerDir `
            -ManifestPath $manifestPath -ExistingManifest $existingManifest -IsRepair $false
    }
}
