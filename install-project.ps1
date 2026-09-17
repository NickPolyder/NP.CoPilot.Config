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

    State is normalized, schema-validated and bound to this repository before
    mutation. Corrupt, unreadable, relocated or orphaned state must be recovered
    explicitly; -Force never bypasses these checks. Valid version-1 manifests
    are upgraded without trusting their historical gitignore-ownership flag.

    Target/state directory ancestors must be ordinary directories, not reparse
    points. File symbolic links are conflicts unless explicitly replaced with
    -Force; their link entries are backed up/restored without writing to the
    referent. File writes replace directory entries atomically, so hard-linked
    aliases do not receive in-place template writes. Restoring a file snapshot
    restores its bytes, not a former hard-link relationship.

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
    Skips Git exclusion management for this run. Personal preferences and
    installer state/backups may be exposed; existing tracked files are never
    removed from the index by this installer.

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
    installer added, if it is still present unmodified and no personal or
    recovery artifacts need its exclusions. Restoration is staged and verified
    before replacement, with retryable checkpoints. Additional foreign backups
    and unrecognized state are retained for explicit recovery, never recursively
    deleted. This is per-artifact recovery, not an all-or-nothing uninstall.

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
$script:RunStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N')
$script:GitignoreMarker = '# Local Copilot preferences (personal, not shared)'
$script:GitignoreEntry = '.github/instructions/local-preferences.instructions.md'
$script:StateIgnoreEntry = '/.np-copilot-project-installer/'
$script:ArtifactNames = @('project-config.instructions.md', 'local-preferences.instructions.md')
$script:PathComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)
# A leading BOM is a logical line boundary; retain indices into the original text.
$script:InstructionLineStart = '(?:^|(?<=\A\uFEFF))'
$script:TxLog = [Collections.Generic.List[object]]::new()
$script:TransientBackups = [Collections.Generic.List[object]]::new()

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
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-BytesHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
}

function Get-PathEntry {
    param([Parameter(Mandatory)][string]$Path)
    try { Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
}

function Assert-DirectoryPath {
    param([Parameter(Mandatory)][string]$Path)
    $current = Get-NormalizedPath -Path $Path
    while ($current) {
        $entry = Get-PathEntry -Path $current
        if ($entry -and (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $entry.PSIsContainer)) {
            throw "Unsafe directory path '$current': directory/reparse-point collision. Use ordinary directories; no changes were authorized through this path."
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Assert-FilePath {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowSymbolicLink)
    Assert-DirectoryPath -Path (Split-Path $Path -Parent)
    $entry = Get-PathEntry -Path $Path
    if (-not $entry) { return }
    if ($entry.PSIsContainer) { throw "Directory collision at file path '$Path'; -Force does not authorize replacing a directory." }
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (-not $AllowSymbolicLink -or $entry.LinkType -ne 'SymbolicLink')) {
        throw "Unsupported reparse-point collision at '$Path'; preserve it and reconcile the path explicitly."
    }
}

function Get-FileIdentity {
    param([Parameter(Mandatory)][string]$Path)
    Assert-FilePath -Path $Path -AllowSymbolicLink
    $entry = Get-PathEntry -Path $Path
    if (-not $entry) { return $null }
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        return [pscustomobject]@{ Kind = 'SymbolicLink'; Hash = $null; LinkTarget = [string]$entry.Target }
    }
    [pscustomobject]@{ Kind = 'File'; Hash = (Get-Sha256FileHash -Path $Path); LinkTarget = $null }
}

function Test-FileIdentity {
    param($Actual, $Expected)
    if (-not $Actual -or -not $Expected -or $Actual.Kind -cne $Expected.Kind) { return $false }
    if ($Actual.Kind -eq 'File') { return $Actual.Hash -ceq $Expected.Hash }
    $Actual.LinkTarget -ceq $Expected.LinkTarget
}

function New-TrackedDirectory {
    param([Parameter(Mandatory)][string]$Path)
    Assert-DirectoryPath -Path $Path
    if (Get-PathEntry -Path $Path) { return }
    $parent = Split-Path $Path -Parent
    if (-not (Get-PathEntry -Path $parent)) { New-TrackedDirectory -Path $parent }
    New-Item -ItemType Directory -Path $Path | Out-Null
    $script:TxLog.Add(@{ Action = 'CreatedDirectory'; Path = $Path })
}

function Write-BytesAtomically {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [string]$StagingDirectory
    )
    Assert-FilePath -Path $Path -AllowSymbolicLink
    if ($StagingDirectory) { New-TrackedDirectory -Path $StagingDirectory }
    else { $StagingDirectory = Split-Path $Path -Parent }
    $temp = Join-Path $StagingDirectory ".np-write-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        Assert-FilePath -Path $Path -AllowSymbolicLink
        [IO.File]::Move($temp, $Path, $true)
    }
    finally {
        if (Get-PathEntry -Path $temp) { Remove-Item -LiteralPath $temp -Force }
    }
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
    $stateDir = Get-StateDir -TargetPath $TargetPath
    Assert-DirectoryPath -Path $stateDir
    $manifestPath = Get-ManifestPath -TargetPath $TargetPath
    Assert-FilePath -Path $manifestPath
    if (-not (Get-PathEntry -Path $manifestPath)) {
        if (Get-PathEntry -Path $stateDir) {
            throw "Installer state exists at '$stateDir' without manifest.json. Preserve the state/backups and recover the original manifest before retrying; -Force cannot bypass recovery."
        }
        return $null
    }
    try {
        $json = $script:Utf8.GetString([IO.File]::ReadAllBytes($manifestPath)).TrimStart([char]0xFEFF)
        $document = [Text.Json.JsonDocument]::Parse($json)
        try { Assert-UniqueJsonMembers -Element $document.RootElement }
        finally { $document.Dispose() }
        $manifest = ConvertFrom-Json -InputObject $json -NoEnumerate
        Assert-ObjectFields -Value $manifest -Fields @('SchemaVersion', 'TargetPath', 'Template', 'CreatedAt', 'UpdatedAt',
            'GitignoreManaged', 'InstructionsDirCreatedByUs', 'Artifacts') -OptionalFields @('GitignorePolicyEnabled',
            'GitignoreEffective', 'GitignoreBlocks', 'RetainedBackups')
        if (($manifest.SchemaVersion -isnot [int] -and $manifest.SchemaVersion -isnot [long]) -or
            $manifest.SchemaVersion -notin @(1, 2)) { throw 'Unsupported manifest SchemaVersion (expected 1 or 2).' }
        $version = $manifest.SchemaVersion
        $newFields = @('GitignorePolicyEnabled', 'GitignoreEffective', 'GitignoreBlocks', 'RetainedBackups')
        if ($version -eq 1 -and @($manifest.PSObject.Properties.Name | Where-Object { $_ -cin $newFields }).Count) {
            throw 'Version-1 manifest contains unsupported version-2 fields.'
        }
        Assert-BoundPath -Path $manifest.TargetPath -Expected $TargetPath
        if ($manifest.Template -cnotin @('Generic', 'Angular', 'Blazor', 'ServiceFabric')) { throw 'Invalid manifest Template.' }
        foreach ($name in @('CreatedAt', 'UpdatedAt')) {
            $date = [DateTimeOffset]::MinValue
            $value = $manifest.$name
            if ($value -is [datetime]) { $value = $value.ToUniversalTime().ToString('o') }
            if ($value -isnot [string] -or -not [DateTimeOffset]::TryParse($value, [ref]$date)) {
                throw "Invalid manifest $name."
            }
            $manifest.$name = $value
        }
        foreach ($name in @('GitignoreManaged', 'InstructionsDirCreatedByUs')) {
            if ($manifest.$name -isnot [bool]) { throw "Invalid manifest $name (expected boolean)." }
        }
        if ($manifest.Artifacts -isnot [array]) { throw 'Invalid manifest Artifacts (expected array).' }
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $backups = [Collections.Generic.HashSet[string]]::new($script:PathComparer)
        foreach ($artifact in $manifest.Artifacts) {
            Assert-ObjectFields -Value $artifact -Fields @('Name', 'TargetPath', 'BackupPath', 'InstalledHash', 'Status') `
                -OptionalFields @('BackupIdentity')
            if (($version -eq 2 -and 'BackupIdentity' -cnotin $artifact.PSObject.Properties.Name) -or
                ($version -eq 1 -and 'BackupIdentity' -cin $artifact.PSObject.Properties.Name)) {
                throw 'BackupIdentity does not match the manifest schema version.'
            }
            if ($artifact.Name -cnotin $script:ArtifactNames -or -not $names.Add($artifact.Name)) {
                throw 'Unknown or duplicate artifact Name.'
            }
            $expected = Join-Path $TargetPath '.github' 'instructions' $artifact.Name
            Assert-BoundPath -Path $artifact.TargetPath -Expected $expected
            $artifact.TargetPath = $expected
            $statuses = if ($version -eq 1) { @('Managed', 'Conflict') } else { @('Managed', 'Conflict', 'RestorePending', 'Restored') }
            if ($artifact.Status -cnotin $statuses) { throw "Invalid artifact Status for '$($artifact.Name)'." }
            if ($null -ne $artifact.InstalledHash -or $artifact.Status -ne 'Conflict') {
                Assert-Hash -Value $artifact.InstalledHash
            }
            if ($null -ne $artifact.BackupPath) {
                $artifact.BackupPath = Get-ValidatedBackupPath -Path $artifact.BackupPath -TargetPath $TargetPath -Name $artifact.Name
                if (-not $backups.Add($artifact.BackupPath)) { throw 'Duplicate backup path.' }
                if ($version -eq 1) {
                    $identity = Get-FileIdentity -Path $artifact.BackupPath
                    if (-not $identity) { throw "Missing recovery backup '$($artifact.BackupPath)'." }
                    $artifact | Add-Member -NotePropertyName BackupIdentity -NotePropertyValue $identity -Force
                }
                else { Assert-BackupIdentity -Value $artifact.BackupIdentity }
            }
            else {
                if ($artifact.Status -in @('RestorePending', 'Restored')) { throw 'Recovery status requires a backup path.' }
                if ($version -eq 2 -and $null -ne $artifact.BackupIdentity) { throw 'BackupIdentity requires a backup path.' }
                $artifact | Add-Member -NotePropertyName BackupIdentity -NotePropertyValue $null -Force
            }
        }
        if ($version -eq 1) {
            # Version 1 could claim a foreign ignore block merely by finding a substring.
            # Keep its privacy policy, but never use that flag as deletion ownership.
            $manifest | Add-Member -NotePropertyName GitignorePolicyEnabled -NotePropertyValue $manifest.GitignoreManaged -Force
            $manifest | Add-Member -NotePropertyName GitignoreEffective -NotePropertyValue $false -Force
            $manifest | Add-Member -NotePropertyName GitignoreBlocks -NotePropertyValue @() -Force
            $manifest | Add-Member -NotePropertyName RetainedBackups -NotePropertyValue @() -Force
            $manifest.GitignoreManaged = $false
        }
        else {
            foreach ($name in @('GitignorePolicyEnabled', 'GitignoreEffective')) {
                if ($manifest.$name -isnot [bool]) { throw "Invalid manifest $name (expected boolean)." }
            }
            if ($manifest.GitignoreBlocks -isnot [array] -or $manifest.RetainedBackups -isnot [array]) {
                throw 'GitignoreBlocks and RetainedBackups must be arrays.'
            }
            $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($block in $manifest.GitignoreBlocks) {
                Assert-ObjectFields -Value $block -Fields @('Id', 'LeadingNewline', 'PrefixHash')
                if ($block.Id -isnot [string] -or $block.Id -cnotmatch '^[a-f0-9]{32}$' -or -not $ids.Add($block.Id)) {
                    throw 'Invalid or duplicate ignore-block identity.'
                }
                if ($block.LeadingNewline -isnot [string] -or $block.LeadingNewline -cnotin @('', "`n")) {
                    throw 'Invalid ignore-block separator.'
                }
                Assert-Hash -Value $block.PrefixHash
            }
            if ($manifest.GitignoreManaged -ne ($manifest.GitignoreBlocks.Count -gt 0)) {
                throw 'GitignoreManaged disagrees with insertion ownership.'
            }
            if ($manifest.GitignoreManaged -and -not $manifest.GitignorePolicyEnabled) {
                throw 'Owned ignore blocks require an enabled exclusion policy.'
            }
            $retained = [Collections.Generic.List[string]]::new()
            foreach ($path in $manifest.RetainedBackups) {
                $validated = Get-ValidatedBackupPath -Path $path -TargetPath $TargetPath
                if (-not $backups.Add($validated)) { throw 'Duplicate retained backup path.' }
                $retained.Add($validated)
            }
            $manifest.RetainedBackups = @($retained.ToArray())
        }
        $manifest.SchemaVersion = 2
        $manifest.TargetPath = $TargetPath
        return $manifest
    }
    catch {
        throw "Invalid or unreadable installer state at '$manifestPath': $($_.Exception.Message) Preserve manifest and backup bytes; recover a valid same-target manifest before retrying. -Force cannot bypass this check."
    }
}

function Assert-UniqueJsonMembers {
    param([Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "Duplicate JSON property '$($property.Name)'." }
            Assert-UniqueJsonMembers -Element $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-UniqueJsonMembers -Element $item }
    }
}

function Assert-ObjectFields {
    param($Value, [string[]]$Fields, [string[]]$OptionalFields = @())
    if ($Value -isnot [pscustomobject]) { throw 'Expected a manifest object.' }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($field in $Fields) {
        if ($field -cnotin $names) { throw "Missing manifest field '$field'." }
    }
    foreach ($name in $names) {
        if ($name -cnotin ($Fields + $OptionalFields)) { throw "Unknown manifest field '$name'." }
    }
}

function Assert-Hash {
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid SHA-256 value.' }
}

function Assert-BackupIdentity {
    param($Value)
    Assert-ObjectFields -Value $Value -Fields @('Kind', 'Hash', 'LinkTarget')
    if ($Value.Kind -ceq 'File') {
        Assert-Hash -Value $Value.Hash
        if ($null -ne $Value.LinkTarget) { throw 'Regular-file backup cannot have a link target.' }
    }
    elseif ($Value.Kind -ceq 'SymbolicLink') {
        if ($null -ne $Value.Hash -or $Value.LinkTarget -isnot [string] -or
            [string]::IsNullOrWhiteSpace($Value.LinkTarget) -or $Value.LinkTarget.Contains([char]0)) {
            throw 'Invalid symbolic-link backup identity.'
        }
    }
    else { throw 'Unsupported backup identity Kind.' }
}

function Assert-BoundPath {
    param($Path, [string]$Expected)
    if ($Path -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($Path) -or
        -not $script:PathComparer.Equals((Get-NormalizedPath -Path $Path), $Expected)) {
        throw "Manifest target binding mismatch: expected '$Expected'. Relocated, relative, or cross-target state cannot be used."
    }
}

function Get-ValidatedBackupPath {
    param($Path, [string]$TargetPath, [string]$Name)
    if ($Path -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw 'Recovery paths must be absolute and bound to this target.'
    }
    $fullPath = Get-NormalizedPath -Path $Path
    $backupRoot = Join-Path (Get-StateDir -TargetPath $TargetPath) 'backups'
    $parts = [IO.Path]::GetRelativePath($backupRoot, $fullPath) -split '[\\/]'
    if ($parts.Count -ne 2 -or $parts[0] -cnotmatch '^[A-Za-z0-9_-]+$' -or
        $parts[1] -cnotin $script:ArtifactNames -or ($Name -and $parts[1] -cne $Name)) {
        throw "Recovery path '$Path' is outside the permitted per-artifact backup layout."
    }
    Assert-FilePath -Path $fullPath -AllowSymbolicLink
    $fullPath
}

function New-ProjectManifestObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory object only; performs no I/O or state mutation. Save-ProjectManifest is the ShouldProcess-gated write.')]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Artifacts,
        [bool]$GitignorePolicyEnabled,
        [bool]$GitignoreEffective,
        [array]$GitignoreBlocks = @(),
        [array]$RetainedBackups = @(),
        [bool]$InstructionsDirCreatedByUs,
        $ExistingManifest
    )

    $createdAt = if ($ExistingManifest -and $ExistingManifest.CreatedAt) { $ExistingManifest.CreatedAt } else { (Get-Date).ToUniversalTime().ToString('o') }

    [pscustomobject]@{
        SchemaVersion              = 2
        TargetPath                 = $TargetPath
        Template                   = $Template
        CreatedAt                  = $createdAt
        UpdatedAt                  = (Get-Date).ToUniversalTime().ToString('o')
        GitignoreManaged           = $GitignoreBlocks.Count -gt 0
        GitignorePolicyEnabled     = $GitignorePolicyEnabled
        GitignoreEffective         = $GitignoreEffective
        GitignoreBlocks            = @($GitignoreBlocks)
        RetainedBackups            = @($RetainedBackups)
        InstructionsDirCreatedByUs = $InstructionsDirCreatedByUs
        Artifacts                  = @($Artifacts)
    }
}

function Save-ManifestFileAtomically {
    <#
    .SYNOPSIS
        Serializes a manifest to JSON and publishes it atomically: the JSON
        is written to a sibling temp file first, and only promoted over the
        real manifest path with a single same-directory rename-replace once
        that write has fully succeeded. A failure at any point
        (serialization, disk full, locked file) leaves a prior manifest at
        ManifestPath, if any, completely unmodified instead of a
        half-written/corrupt file.
    .NOTES
        Deliberately uses [System.IO.File]::Move(source, dest, $true) rather
        than Move-Item -Force: PowerShell's FileSystemProvider can satisfy
        -Force by deleting the destination and then moving, which is two
        separate operations with a window where ManifestPath would be
        missing if interrupted between them. The 3-arg File.Move overload
        (available since .NET Core 3.0, which this script's
        `#Requires -Version 7.0` guarantees) maps to a single OS-level
        rename-replace call (MoveFileEx/MOVEFILE_REPLACE_EXISTING on
        Windows, rename(2) on POSIX) that either fully succeeds or fully
        fails, and covers both first publication (no prior file) and
        replacing an existing one.
    #>
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    $dir = Split-Path $ManifestPath -Parent
    Assert-FilePath -Path $ManifestPath
    New-TrackedDirectory -Path $dir
    $tempPath = Join-Path $dir ".manifest-$([guid]::NewGuid().ToString('N')).tmp"
    $published = $false
    try {
        $Manifest.UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        [IO.File]::WriteAllText($tempPath, ($Manifest | ConvertTo-Json -Depth 10), $script:Utf8)
        Assert-FilePath -Path $ManifestPath
        [System.IO.File]::Move($tempPath, $ManifestPath, $true)
        $published = $true
    }
    finally {
        if (-not $published -and (Get-PathEntry -Path $tempPath)) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Save-ProjectManifest {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )
    if ($PSCmdlet.ShouldProcess($ManifestPath, 'Write install manifest')) {
        Save-ManifestFileAtomically -Manifest $Manifest -ManifestPath $ManifestPath
    }
}

# ---------------------------------------------------------------------------
# Transaction log (created-this-run artifacts only; rolled back on failure)
# ---------------------------------------------------------------------------

function Undo-Transaction {
    if (-not $script:TxLog -or $script:TxLog.Count -eq 0) { return }

    Write-Host "`n↩️  Rolling back changes made during this run..." -ForegroundColor Yellow
    $failures = [Collections.Generic.List[string]]::new()
    for ($i = $script:TxLog.Count - 1; $i -ge 0; $i--) {
        $entry = $script:TxLog[$i]
        try {
            switch ($entry.Action) {
                'CreatedDirectory' {
                    if (Get-PathEntry -Path $entry.Path) {
                        Assert-DirectoryPath -Path $entry.Path
                        if (@(Get-ChildItem -LiteralPath $entry.Path -Force).Count) {
                            throw "Directory is not empty; retained '$($entry.Path)' rather than recursively deleting recovery or foreign content."
                        }
                        Remove-Item -LiteralPath $entry.Path -Force
                    }
                }
                'WroteFile' {
                    $current = Get-FileIdentity -Path $entry.Path
                    if ($current -and -not (Test-FileIdentity -Actual $current -Expected $entry.WrittenIdentity)) {
                        throw 'Target changed after this run wrote it; recovery copies were retained.'
                    }
                    if ($entry.PreviousContentPath) {
                        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $entry.PreviousContentPath) -Expected $entry.PreviousIdentity)) {
                            throw "Rollback backup is missing or changed: '$($entry.PreviousContentPath)'."
                        }
                        [IO.File]::Move($entry.PreviousContentPath, $entry.Path, $true)
                    }
                    elseif ($current) { Remove-Item -LiteralPath $entry.Path -Force }
                }
                'CreatedBackup' {
                    if (Get-PathEntry -Path $entry.Path) {
                        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $entry.SourcePath) -Expected $entry.Identity)) {
                            throw "Original changed; retained recovery copy '$($entry.Path)'."
                        }
                        Remove-Item -LiteralPath $entry.Path -Force
                    }
                }
                'AppendedGitignore' {
                    Assert-FilePath -Path $entry.Path
                    if ((Get-Sha256FileHash -Path $entry.Path) -ne $entry.WrittenHash) {
                        throw 'Gitignore changed after this run wrote it; refusing to overwrite intervening edits.'
                    }
                    if ($null -eq $entry.PreviousBytes) {
                        Remove-Item -LiteralPath $entry.Path -Force
                    }
                    else {
                        Write-BytesAtomically -Path $entry.Path -Bytes $entry.PreviousBytes
                    }
                }
            }
            Write-Status '↩️' "Reverted $($entry.Action): $($entry.Path)"
        }
        catch {
            Write-Status '❌' "Rollback step failed for $($entry.Path): $($_.Exception.Message)"
            $failures.Add("$($entry.Path): $($_.Exception.Message)")
        }
    }
    if ($failures.Count) { throw "Rollback incomplete; preserve the reported recovery paths. $($failures -join '; ')" }
    $script:TxLog.Clear()
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

function Test-ProjectInstallPreflight {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TemplateDir,
        [Parameter(Mandatory)][string]$Template
    )

    $problems = [System.Collections.Generic.List[string]]::new()

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
        Assert-FilePath -Path $sourcePath
        if (-not (Get-PathEntry -Path $sourcePath)) { throw "Required template not found: '$sourcePath'. Existing ownership and recovery records were not changed." }
        $bytes = [IO.File]::ReadAllBytes($sourcePath)
        if ($item.Target -eq 'project-config.instructions.md') {
            $bytes = Get-ProjectConfigBytes -Bytes $bytes -TargetPath $TargetPath
        }
        $resolved += [pscustomobject]@{ Name = $item.Target; Bytes = $bytes }
    }

    return $resolved
}

function Test-ProjectTargetPreflight {
    param([string]$TargetPath, $Manifest)
    Assert-DirectoryPath -Path $TargetPath
    if (-not (Get-PathEntry -Path $TargetPath)) { throw "Target path does not exist: '$TargetPath'." }
    if (-not (Get-PathEntry -Path (Join-Path $TargetPath '.git'))) { throw "'$TargetPath' is not a git repository (no .git found)." }
    $gitRoot = Invoke-ProjectGit -TargetPath $TargetPath -Arguments @('rev-parse', '--show-toplevel')
    if ($gitRoot.ExitCode -ne 0 -or
        -not $script:PathComparer.Equals((Get-NormalizedPath -Path $gitRoot.Output.Trim()), $TargetPath)) {
        throw "Target must be the requested Git worktree root. $($gitRoot.Error)"
    }
    foreach ($name in $script:ArtifactNames) {
        Assert-FilePath -Path (Join-Path $TargetPath '.github' 'instructions' $name) -AllowSymbolicLink
    }
    Assert-FilePath -Path (Join-Path $TargetPath '.gitignore')
    Assert-DirectoryPath -Path (Join-Path (Get-StateDir -TargetPath $TargetPath) 'backups')
    if ($Manifest) {
        foreach ($artifact in $Manifest.Artifacts) {
            if (-not $artifact.BackupPath) { continue }
            $actual = Get-FileIdentity -Path $artifact.BackupPath
            if (-not $actual -and $artifact.Status -eq 'Restored') { continue }
            if (-not (Test-FileIdentity -Actual $actual -Expected $artifact.BackupIdentity)) {
                throw "Recovery backup is missing or changed: '$($artifact.BackupPath)'. Preserve state and recover the recorded original before retrying."
            }
        }
    }
}

function Get-CapabilitySection {
    param([string]$Content)
    [regex]::Match($Content, ('(?ims)' + $script:InstructionLineStart + '## (?:Agent )?Delivery capabilities[ \t]*\r?\n.*?(?=^##[ \t]|\z)'))
}

function Get-CapabilityOwner {
    param([string]$Section)
    $matches = [regex]::Matches($Section, ('(?m)' + $script:InstructionLineStart + '<!-- np-copilot-capabilities-owner: ([^\r\n]+) -->[ \t]*\r?$'))
    $labels = [regex]::Matches($Section, '(?i)np-copilot-capabilities-owner')
    if ($matches.Count -gt 1) { throw 'Multiple capability-owner markers in one section; reconcile them before installing.' }
    if ($labels.Count -ne $matches.Count) { throw 'Malformed capability-owner marker; reconcile it before installing.' }
    if ($matches.Count -eq 0) { return $null }
    $owner = $matches[0].Groups[1].Value
    if ($owner -cnotin @('.github/instructions/project-config.instructions.md', '.github/copilot-instructions.md')) {
        throw "Unknown capability owner '$owner'."
    }
    $owner
}

function Assert-AdditionalCapabilityContracts {
    param([string]$TargetPath, [bool]$ProjectDeclares, [bool]$RootDeclares)
    foreach ($name in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
        $path = Join-Path $TargetPath $name
        Assert-FilePath -Path $path
        if (-not (Get-PathEntry -Path $path)) { continue }
        $content = $script:Utf8.GetString([IO.File]::ReadAllBytes($path))
        $hasTable = $content -match ('(?im)' + $script:InstructionLineStart + '\|[ \t]*Capability[ \t]*\|[ \t]*Enabled[ \t]*\|')
        $hasSection = $content -match ('(?im)' + $script:InstructionLineStart + '#{1,6}[ \t]+(?:Agent[ \t]+)?Delivery[ \t]+capabilities\b')
        if ($hasTable) {
            throw "Root contract '$name' declares delivery capabilities outside the two-path owner protocol. Preserve its values and resolve an explicit reference/migration plan with repo-bootstrap before installing; -Force cannot add competing defaults."
        }
        $owner = Get-CapabilityOwner -Section $content
        if ($hasSection -and -not $owner) {
            throw "Root contract '$name' has an unrepresented delivery-capability section. Preserve it and resolve an explicit reference/migration plan with repo-bootstrap before installing."
        }
        if (($owner -eq '.github/instructions/project-config.instructions.md' -and -not $ProjectDeclares) -or
            ($owner -eq '.github/copilot-instructions.md' -and -not $RootDeclares)) {
            throw "Delivery-capability reference in '$name' has no declaration at its owner. Reconcile the source before installing."
        }
    }
}

function Get-ProjectConfigBytes {
    param([byte[]]$Bytes, [string]$TargetPath)
    $projectOwner = '.github/instructions/project-config.instructions.md'
    $rootOwner = '.github/copilot-instructions.md'
    $projectPath = Join-Path $TargetPath '.github' 'instructions' 'project-config.instructions.md'
    $rootPath = Join-Path $TargetPath '.github' 'copilot-instructions.md'
    $projectSection = ''
    $rootSection = ''
    $projectEntry = Get-PathEntry -Path $projectPath
    if ($projectEntry -and -not ($projectEntry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $projectSection = (Get-CapabilitySection -Content $script:Utf8.GetString([IO.File]::ReadAllBytes($projectPath))).Value
    }
    Assert-FilePath -Path $rootPath
    if (Get-PathEntry -Path $rootPath) {
        $rootSection = (Get-CapabilitySection -Content $script:Utf8.GetString([IO.File]::ReadAllBytes($rootPath))).Value
    }
    $projectMarker = Get-CapabilityOwner -Section $projectSection
    $rootMarker = Get-CapabilityOwner -Section $rootSection
    $tablePattern = '(?im)' + $script:InstructionLineStart + '\|[ \t]*Capability[ \t]*\|[ \t]*Enabled[ \t]*\|'
    $projectDeclares = $projectSection -match $tablePattern
    $rootDeclares = $rootSection -match $tablePattern
    Assert-AdditionalCapabilityContracts -TargetPath $TargetPath -ProjectDeclares $projectDeclares -RootDeclares $rootDeclares
    if (($projectSection -and -not $projectDeclares -and -not $projectMarker) -or
        ($rootSection -and -not $rootDeclares -and -not $rootMarker)) {
        throw 'Unrepresented delivery-capability section. Preserve its existing rules and resolve an explicit owner/reference plan before installing.'
    }
    if (($projectDeclares -and $rootDeclares) -or
        ($projectMarker -eq $projectOwner -and $rootMarker -eq $rootOwner) -or
        ($projectDeclares -and $projectMarker -eq $rootOwner) -or
        ($rootDeclares -and $rootMarker -eq $projectOwner)) {
        throw 'Conflicting delivery-capability owners. Preserve verified values and replace the non-owner declaration with a reference before installing; -Force cannot reset them.'
    }
    if (($projectMarker -eq $rootOwner -and -not $rootDeclares) -or
        ($rootMarker -eq $rootOwner -and -not $rootDeclares) -or
        ($rootMarker -eq $projectOwner -and -not $projectDeclares) -or
        ($projectMarker -eq $projectOwner -and -not $projectDeclares)) {
        throw 'Delivery-capability reference has no declaration at its owner. Reconcile the source before installing.'
    }
    $content = $script:Utf8.GetString($Bytes)
    $sourceSection = Get-CapabilitySection -Content $content
    if (-not $sourceSection.Success) {
        if ($projectDeclares -or $rootDeclares) { throw 'Template lacks a capability section; refusing to discard the existing capability owner.' }
        return ,$Bytes
    }
    $replacement = $sourceSection.Value
    if ($rootDeclares) {
        $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
        $replacement = @('## Agent Delivery Capabilities', '',
            "<!-- np-copilot-capabilities-owner: $rootOwner -->", '',
            'The [root project contract](../copilot-instructions.md) owns the verified delivery capabilities.',
            'Use that declaration; this file does not add a second capability table or override its values.', '', '') -join $newline
    }
    elseif ($projectDeclares) {
        $replacement = $projectSection
        if (-not $projectMarker) {
            $replacement = [regex]::Replace($replacement, '(^[^\r\n]+\r?\n)',
                "`$1`n<!-- np-copilot-capabilities-owner: $projectOwner -->`n", 1)
        }
    }
    if ($replacement -ceq $sourceSection.Value) { return ,$Bytes }
    $updated = $content.Substring(0, $sourceSection.Index) + $replacement +
        $content.Substring($sourceSection.Index + $sourceSection.Length)
    return ,$script:Utf8.GetBytes($updated)
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

function New-ArtifactBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)]$Identity
    )

    $name = Split-Path $Path -Leaf
    $destination = Join-Path $BackupDir $name

    if ($PSCmdlet.ShouldProcess($Path, "Back up to $destination")) {
        New-TrackedDirectory -Path $BackupDir
        Copy-FileEntry -SourcePath $Path -Destination $destination -Identity $Identity
        $script:TxLog.Add(@{ Action = 'CreatedBackup'; Path = $destination; SourcePath = $Path; Identity = $Identity })
        Write-Status '📦' "Backed up existing file to: $destination"
    }

    return $destination
}

function Copy-FileEntry {
    param([string]$SourcePath, [string]$Destination, $Identity)
    Assert-FilePath -Path $SourcePath -AllowSymbolicLink
    Assert-FilePath -Path $Destination -AllowSymbolicLink
    if (Get-PathEntry -Path $Destination) { throw "Backup/staging collision at '$Destination'." }
    $complete = $false
    try {
        if ($Identity.Kind -eq 'SymbolicLink') {
            # Preserve the link entry and its raw relative/absolute target, not its referent.
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Identity.LinkTarget | Out-Null
        }
        else { [IO.File]::Copy($SourcePath, $Destination, $false) }
        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $Destination) -Expected $Identity)) {
            throw "Source changed while copying '$SourcePath'; no target replacement was authorized."
        }
        $complete = $true
    }
    finally {
        if (-not $complete -and (Get-PathEntry -Path $Destination)) { Remove-Item -LiteralPath $Destination -Force }
    }
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
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$BackupDir,
        [switch]$Force,
        $PreviousArtifact
    )

    $sourceHash = Get-BytesHash -Bytes $Bytes
    $stagingDirectory = Split-Path (Split-Path $BackupDir -Parent) -Parent
    $carriedBackupPath = if ($PreviousArtifact) { $PreviousArtifact.BackupPath } else { $null }
    $backupIdentity = if ($PreviousArtifact) { $PreviousArtifact.BackupIdentity } else { $null }
    $current = Get-FileIdentity -Path $TargetPath
    $installedIdentity = [pscustomobject]@{ Kind = 'File'; Hash = $sourceHash; LinkTarget = $null }
    if (-not $current) {
        if ($PSCmdlet.ShouldProcess($TargetPath, "Install $Name")) {
            $dir = Split-Path $TargetPath -Parent
            New-TrackedDirectory -Path $dir
            Write-BytesAtomically -Path $TargetPath -Bytes $Bytes -StagingDirectory $stagingDirectory
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $null; WrittenIdentity = $installedIdentity })
            Write-Status '✅' "$Name -> installed"
        }
        return [pscustomobject]@{
            Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath; BackupIdentity = $backupIdentity
            InstalledHash = $sourceHash; Status = 'Managed'
        }
    }

    $ownedUnmodified = $PreviousArtifact -and $PreviousArtifact.Status -eq 'Managed' -and
        $current.Kind -eq 'File' -and $current.Hash -eq $PreviousArtifact.InstalledHash
    $matchesSource = $current.Kind -eq 'File' -and $current.Hash -eq $sourceHash
    if ($ownedUnmodified -and $matchesSource) {
        Write-Status 'ℹ️' "$Name already up to date."
        return $PreviousArtifact
    }
    if ($ownedUnmodified -or $Force) {
        $verb = if ($ownedUnmodified) { 'Refresh' } else { 'Overwrite' }
        if ($PSCmdlet.ShouldProcess($TargetPath, "$verb $Name")) {
            $runBackupPath = New-ArtifactBackup -Path $TargetPath -BackupDir $BackupDir -Identity $current
            Write-BytesAtomically -Path $TargetPath -Bytes $Bytes -StagingDirectory $stagingDirectory
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $runBackupPath
                    PreviousIdentity = $current; WrittenIdentity = $installedIdentity })
            if ($ownedUnmodified) {
                $script:TransientBackups.Add(@{ Path = $runBackupPath; Identity = $current })
                Write-Status '🔄' "$Name refreshed to current template."
            }
            else {
                if ($carriedBackupPath) { $script:RetainedBackups.Add($runBackupPath) }
                else { $carriedBackupPath = $runBackupPath; $backupIdentity = $current }
                if ($matchesSource) { Write-Status '✅' "$Name adopted (-Force); already matches current template. Original backed up." }
                else { Write-Status '✅' "$Name overwritten (-Force); previous content backed up." }
            }
        }
        return [pscustomobject]@{
            Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath; BackupIdentity = $backupIdentity
            InstalledHash = $sourceHash; Status = 'Managed'
        }
    }

    if ($matchesSource) {
        Write-Status 'ℹ️' "$Name matches the current template but was never taken over by the installer; leaving ownership unchanged. Use -Force to adopt it explicitly."
    }
    elseif ($current.Kind -eq 'SymbolicLink') {
        Write-Status '⚠️' "$Name is a foreign symbolic link; leaving the link and its referent untouched. Use -Force to back up and replace the link entry explicitly."
    }
    else { Write-Status '⚠️' "$Name already exists with different content; leaving as-is. Use -Force to overwrite (a backup will be made first)." }
    return [pscustomobject]@{
        Name = $Name; TargetPath = $TargetPath; BackupPath = $carriedBackupPath; BackupIdentity = $backupIdentity
        InstalledHash = $current.Hash; Status = 'Conflict'
    }
}

function Invoke-ProjectGit {
    param([string]$TargetPath, [string[]]$Arguments)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('--no-pager', '--no-optional-locks', '-C', $TargetPath, '-c', 'core.fsmonitor=false') + $Arguments) {
        $info.ArgumentList.Add($argument)
    }
    foreach ($name in @($info.Environment.Keys)) {
        if ($name -match '^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|CEILING_DIRECTORIES|DISCOVERY_ACROSS_FILESYSTEM|CONFIG|CONFIG_COUNT|CONFIG_PARAMETERS|CONFIG_KEY_\d+|CONFIG_VALUE_\d+|EXEC_PATH)$') {
            $info.Environment.Remove($name) | Out-Null
        }
    }
    $info.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not start Git for exclusion verification.' }
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorOutput = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output.GetAwaiter().GetResult(); Error = $errorOutput.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Get-GitProtection {
    param([string]$TargetPath)
    $rulesEffective = $true
    # Query the real directory without a trailing slash: state/* can match the
    # synthetic state/ path while still allowing negated children such as staging.
    foreach ($path in @($script:GitignoreEntry, $script:StateDirName)) {
        $result = Invoke-ProjectGit -TargetPath $TargetPath -Arguments @('check-ignore', '--quiet', '--no-index', '--', $path)
        if ($result.ExitCode -eq 1) { $rulesEffective = $false }
        elseif ($result.ExitCode -ne 0) { throw "Git exclusion verification failed for '$path': $($result.Error)" }
    }
    $tracked = Invoke-ProjectGit -TargetPath $TargetPath -Arguments @('ls-files', '--cached', '-z', '--',
        $script:GitignoreEntry, $script:StateDirName)
    if ($tracked.ExitCode -ne 0) { throw "Could not check tracked personal artifacts: $($tracked.Error)" }
    $trackedPaths = @($tracked.Output -split "`0" | Where-Object { $_ })
    [pscustomobject]@{ RulesEffective = $rulesEffective; TrackedPaths = $trackedPaths; Effective = $rulesEffective -and $trackedPaths.Count -eq 0 }
}

function Write-GitProtectionStatus {
    param($Protection)
    if ($Protection.TrackedPaths.Count) {
        Write-Status '⚠️' "Private paths are already tracked; ignore rules cannot protect them and the Git index was NOT changed: $($Protection.TrackedPaths -join ', ')"
    }
    elseif ($Protection.Effective) {
        Write-Status '✅' 'Git exclusions verified for local preferences and installer state/backups.'
    }
    else {
        Write-Status '⚠️' 'Effective Git exclusion is not established for local preferences and installer state/backups.'
    }
}

function Get-GitignoreBlockLines {
    param([string]$Id)
    @("# BEGIN NP Copilot project installer $Id", $script:GitignoreMarker, $script:GitignoreEntry,
        $script:StateIgnoreEntry, "# END NP Copilot project installer $Id")
}

function Get-GitignoreBlockPattern {
    param([string]$Id)
    '(?m)^' + ((Get-GitignoreBlockLines -Id $Id | ForEach-Object { [regex]::Escape($_) }) -join '\r?\n') + '(?:\r?\n|\z)'
}

function Set-GitignoreEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$TargetPath, [array]$Blocks = @())
    if ($WhatIfPreference -and -not (Get-PathEntry -Path (Get-StateDir -TargetPath $TargetPath))) {
        $PSCmdlet.ShouldProcess((Join-Path $TargetPath '.gitignore'), 'Verify complete directory exclusion after creating empty state; append owned exclusions only if needed') | Out-Null
        return [pscustomobject]@{ Blocks = $Blocks; Protection = (Get-GitProtection -TargetPath $TargetPath) }
    }
    $protection = Get-GitProtection -TargetPath $TargetPath
    if ($protection.RulesEffective) {
        Write-Status 'ℹ️' 'Effective Git exclusions already cover local preferences and installer state/backups; no ignore text adopted or appended.'
        return [pscustomobject]@{ Blocks = $Blocks; Protection = $protection }
    }
    $path = Join-Path $TargetPath '.gitignore'
    Assert-FilePath -Path $path
    $previousBytes = $null
    if (Get-PathEntry -Path $path) { $previousBytes = [IO.File]::ReadAllBytes($path) }
    $content = if ($null -ne $previousBytes) { $script:Utf8.GetString($previousBytes) } else { '' }
    $separator = if ($content.Length -and -not $content.EndsWith("`n")) { "`n" } else { '' }
    $block = [pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); LeadingNewline = $separator
        PrefixHash = (Get-BytesHash -Bytes $script:Utf8.GetBytes($content)) }
    if ($PSCmdlet.ShouldProcess($path, 'Append owned exclusions for personal preferences and installer state/backups')) {
        $bytes = $script:Utf8.GetBytes($content + $separator + ((Get-GitignoreBlockLines -Id $block.Id) -join "`n") + "`n")
        Write-BytesAtomically -Path $path -Bytes $bytes
        $script:TxLog.Add(@{ Action = 'AppendedGitignore'; Path = $path; PreviousBytes = $previousBytes; WrittenHash = (Get-BytesHash -Bytes $bytes) })
        $Blocks = @($Blocks) + $block
        $protection = Get-GitProtection -TargetPath $TargetPath
        if (-not $protection.RulesEffective) {
            throw 'Effective Git exclusion could not be established. Reconcile overriding/nested ignore rules before installing personal files; the attempted insertion will be rolled back.'
        }
        Write-Status '✅' 'Appended owned Git exclusions for local preferences and installer state/backups.'
    }
    [pscustomobject]@{ Blocks = $Blocks; Protection = $protection }
}

function Remove-EmptyDirectory {
    param([string]$Path)
    if (-not (Get-PathEntry -Path $Path)) { return }
    Assert-DirectoryPath -Path $Path
    if (@(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) { Remove-Item -LiteralPath $Path -Force }
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

    $existingManifest = Import-ProjectManifest -TargetPath $TargetPath
    Test-ProjectTargetPreflight -TargetPath $TargetPath -Manifest $existingManifest
    if ($existingManifest -and @($existingManifest.Artifacts | Where-Object { $_.Status -in @('RestorePending', 'Restored') }).Count) {
        throw 'A prior uninstall has pending recovery checkpoints. Retry -Uninstall before installing; -Force cannot discard recovery state.'
    }
    $items = @(Test-ProjectInstallPreflight -TargetPath $TargetPath -TemplateDir $TemplateDir -Template $Template)
    Write-Status 'ℹ️' 'Preflight checks passed.'
    $instructionsDir = Join-Path $TargetPath '.github' 'instructions'
    $stateDir = Get-StateDir -TargetPath $TargetPath
    $backupDir = Join-Path $stateDir "backups\$script:RunStamp"
    $instructionsDirCreatedByUs = ($existingManifest -and $existingManifest.InstructionsDirCreatedByUs) -or
        -not (Get-PathEntry -Path $instructionsDir)
    $blocks = @()
    if ($existingManifest) { $blocks = @($existingManifest.GitignoreBlocks) }
    $policyEnabled = -not $SkipGitignore -or ($existingManifest -and $existingManifest.GitignorePolicyEnabled)
    $script:RetainedBackups = [Collections.Generic.List[string]]::new()
    if ($existingManifest) {
        foreach ($path in $existingManifest.RetainedBackups) { $script:RetainedBackups.Add($path) }
    }
    $artifacts = @()
    try {
        if (-not (Get-PathEntry -Path $stateDir) -and $PSCmdlet.ShouldProcess($stateDir, 'Create empty installer state directory')) {
            New-TrackedDirectory -Path $stateDir
        }
        if ($SkipGitignore) {
            Write-Status '⚠️' 'Git exclusion management skipped (-SkipGitignore). Personal preferences and installer state/backups may be exposed; verify Git status before storing personal data.'
            $protection = Get-GitProtection -TargetPath $TargetPath
        }
        else {
            $ignore = Set-GitignoreEntry -TargetPath $TargetPath -Blocks $blocks
            $blocks = @($ignore.Blocks)
            $protection = $ignore.Protection
        }
        foreach ($item in $items) {
            $prevArtifact = $null
            if ($existingManifest) {
                $prevArtifact = @($existingManifest.Artifacts) | Where-Object { $_.Name -eq $item.Name } | Select-Object -First 1
            }
            $targetFilePath = Join-Path $instructionsDir $item.Name
            $artifact = Install-ProjectFile -Name $item.Name -Bytes $item.Bytes -TargetPath $targetFilePath `
                -BackupDir $backupDir -Force:$Force -PreviousArtifact $prevArtifact
            $artifacts += $artifact
        }
        if ($WhatIfPreference) {
            Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
            return
        }

        $manifest = New-ProjectManifestObject -TargetPath $TargetPath -Template $Template -Artifacts $artifacts `
            -GitignorePolicyEnabled ([bool]$policyEnabled) -GitignoreEffective ([bool]$protection.Effective) `
            -GitignoreBlocks $blocks -RetainedBackups @($script:RetainedBackups.ToArray()) `
            -InstructionsDirCreatedByUs ([bool]$instructionsDirCreatedByUs) `
            -ExistingManifest $existingManifest
        Save-ProjectManifest -Manifest $manifest -ManifestPath (Get-ManifestPath -TargetPath $TargetPath)
    }
    catch {
        $failure = $_
        Write-Status '❌' "Install step failed: $($failure.Exception.Message)"
        try { Undo-Transaction }
        catch { throw "Install failed: $($failure.Exception.Message) $($_.Exception.Message)" }
        throw $failure
    }
    $script:TxLog.Clear()
    foreach ($backup in $script:TransientBackups) {
        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $backup.Path) -Expected $backup.Identity)) {
            throw "Transient backup changed; retained '$($backup.Path)' for inspection."
        }
        Remove-Item -LiteralPath $backup.Path -Force
        Remove-EmptyDirectory -Path (Split-Path $backup.Path -Parent)
    }
    Remove-EmptyDirectory -Path (Join-Path $stateDir 'backups')
    $conflicts = @($artifacts | Where-Object { $_.Status -eq 'Conflict' })
    if ($conflicts.Count -gt 0) {
        Write-Status '⚠️' "Left unchanged (not owned by the installer; use -Force to adopt): $($conflicts.Name -join ', ')"
    }

    Write-Host "`n✅ Project templates installed (template: $Template).`n" -ForegroundColor Green
    if (-not $SkipGitignore) { Write-GitProtectionStatus -Protection $protection }
    elseif ($protection.TrackedPaths.Count) {
        Write-Status '⚠️' "Private paths are already tracked; the Git index was NOT changed: $($protection.TrackedPaths -join ', ')"
    }
    Write-Host 'Next steps:' -ForegroundColor Yellow
    Write-Host '  1. Edit .github/instructions/project-config.instructions.md with your project settings'
    Write-Host '  2. Edit .github/instructions/local-preferences.instructions.md with your personal preferences'
    Write-Host "  3. Review Git status before committing project-config.instructions.md; do not add personal files or installer state.`n"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

function Get-GitignoreRemoval {
    param([string]$TargetPath, [array]$Blocks)
    $path = Join-Path $TargetPath '.gitignore'
    Assert-FilePath -Path $path
    if (-not (Get-PathEntry -Path $path)) { return [pscustomobject]@{ CanRemove = $true; Changed = $false; Bytes = $null } }
    $original = $script:Utf8.GetString([IO.File]::ReadAllBytes($path))
    $content = $original
    foreach ($block in $Blocks) {
        $matches = [regex]::Matches($content, (Get-GitignoreBlockPattern -Id $block.Id))
        if ($matches.Count -gt 1 -or ($matches.Count -eq 0 -and $content.Contains($block.Id))) {
            Write-Status '⚠️' 'An owned ignore block was edited or duplicated; leaving .gitignore and recovery state intact.'
            return [pscustomobject]@{ CanRemove = $false; Changed = $false; Bytes = $null }
        }
        if ($matches.Count -eq 0) { continue }
        $start = $matches[0].Index
        $length = $matches[0].Length
        if ($block.LeadingNewline -and $start -gt 0 -and $content.Substring($start - 1, 1) -ceq $block.LeadingNewline -and
            (Get-BytesHash -Bytes $script:Utf8.GetBytes($content.Substring(0, $start - 1))) -ceq $block.PrefixHash) {
            $start--
            $length++
        }
        $content = $content.Remove($start, $length)
    }
    [pscustomobject]@{ CanRemove = $true; Changed = $content -cne $original; Bytes = $script:Utf8.GetBytes($content) }
}

function Save-UninstallCheckpoint {
    param($Manifest)
    Save-ProjectManifest -Manifest $Manifest -ManifestPath (Get-ManifestPath -TargetPath $Manifest.TargetPath)
}

function Complete-ProjectRestoration {
    param($Manifest, $Artifact)
    if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $Artifact.TargetPath) -Expected $Artifact.BackupIdentity)) {
        throw "Restored target changed; retained recovery state for '$($Artifact.Name)'."
    }
    if (Get-PathEntry -Path $Artifact.BackupPath) {
        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $Artifact.BackupPath) -Expected $Artifact.BackupIdentity)) {
            throw "Recovery backup changed: '$($Artifact.BackupPath)'."
        }
        Remove-Item -LiteralPath $Artifact.BackupPath -Force
    }
    Remove-EmptyDirectory -Path (Split-Path $Artifact.BackupPath -Parent)
    $Manifest.Artifacts = @($Manifest.Artifacts | Where-Object { $_.Name -cne $Artifact.Name })
    Save-UninstallCheckpoint -Manifest $Manifest
}

function Restore-ProjectArtifact {
    param($Manifest, $Artifact, $CurrentIdentity)
    $path = $Artifact.TargetPath
    New-TrackedDirectory -Path (Split-Path $path -Parent)
    # Personal restore bytes must remain excluded even while staging. Both paths
    # are inside the same guarded target filesystem, so promotion is still atomic.
    $stage = Join-Path (Get-StateDir -TargetPath $Manifest.TargetPath) ".np-restore-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Copy-FileEntry -SourcePath $Artifact.BackupPath -Destination $stage -Identity $Artifact.BackupIdentity
        $Artifact.Status = 'RestorePending'
        Save-UninstallCheckpoint -Manifest $Manifest
        $now = Get-FileIdentity -Path $path
        if (($now -or $CurrentIdentity) -and -not (Test-FileIdentity -Actual $now -Expected $CurrentIdentity)) {
            throw "Target changed while staging restoration: '$path'. Recovery remains pending."
        }
        [IO.File]::Move($stage, $path, $true)
        if (-not (Test-FileIdentity -Actual (Get-FileIdentity -Path $path) -Expected $Artifact.BackupIdentity)) {
            throw "Restoration verification failed for '$path'; original backup and pending state were retained."
        }
        $Artifact.Status = 'Restored'
        Save-UninstallCheckpoint -Manifest $Manifest
        Complete-ProjectRestoration -Manifest $Manifest -Artifact $Artifact
        Write-Status '♻️' "Restored previous content to $path"
    }
    finally {
        if (Get-PathEntry -Path $stage) { Remove-Item -LiteralPath $stage -Force }
    }
}

function Invoke-ProjectUninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TargetPath)

    Write-Host "`n🗑️  Uninstalling Copilot project templates..." -ForegroundColor Cyan
    Write-Host "   Target: $TargetPath`n"

    $manifest = Import-ProjectManifest -TargetPath $TargetPath
    Test-ProjectTargetPreflight -TargetPath $TargetPath -Manifest $manifest
    $instructionsDir = Join-Path $TargetPath '.github' 'instructions'

    if (-not $manifest) {
        Write-Status 'ℹ️' 'No installer manifest found; nothing tracked to uninstall.'
        Write-Status 'ℹ️' "If files remain at $instructionsDir, remove them manually after reviewing their content."
        return
    }

    $stateDir = Get-StateDir -TargetPath $TargetPath
    if ($WhatIfPreference) {
        foreach ($artifact in $manifest.Artifacts) {
            $PSCmdlet.ShouldProcess($artifact.TargetPath, 'Reconcile owned file and restore any pending original without discarding conflicts') | Out-Null
        }
        $PSCmdlet.ShouldProcess($stateDir, 'Prune only completed recovery records; retain exclusions while private artifacts remain') | Out-Null
        Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
        return
    }
    if (-not $PSCmdlet.ShouldProcess($TargetPath, 'Uninstall tracked project templates with recovery checkpoints')) { return }
    try {
        if ($manifest.GitignorePolicyEnabled) {
            $ignore = Set-GitignoreEntry -TargetPath $TargetPath -Blocks $manifest.GitignoreBlocks
            $manifest.GitignoreBlocks = @($ignore.Blocks)
            $manifest.GitignoreManaged = $manifest.GitignoreBlocks.Count -gt 0
            $manifest.GitignoreEffective = $ignore.Protection.Effective
            Write-GitProtectionStatus -Protection $ignore.Protection
        }
        Save-UninstallCheckpoint -Manifest $manifest
    }
    catch {
        $failure = $_
        try { Undo-Transaction }
        catch { throw "Uninstall preflight publication failed: $($failure.Exception.Message) $($_.Exception.Message)" }
        throw $failure
    }
    $script:TxLog.Clear()
    foreach ($artifact in @($manifest.Artifacts)) {
        $path = $artifact.TargetPath
        $current = Get-FileIdentity -Path $path
        if ($artifact.Status -eq 'Conflict') {
            if (-not $current -and -not $artifact.BackupPath) {
                $manifest.Artifacts = @($manifest.Artifacts | Where-Object { $_.Name -cne $artifact.Name })
                Save-UninstallCheckpoint -Manifest $manifest
            }
            elseif (-not $current) {
                Write-Status '⚠️' "$($artifact.Name) is missing but has a conflicted recovery record. Original retained at '$($artifact.BackupPath)'; reconcile the record explicitly before cleanup."
            }
            else {
                Write-Status '⚠️' "$($artifact.Name) was never taken over by the installer (existing content differed at last run); leaving it in place untouched. Any recovery backup remains tracked."
            }
            continue
        }
        if ($artifact.BackupPath -and (Test-FileIdentity -Actual $current -Expected $artifact.BackupIdentity)) {
            $artifact.Status = 'Restored'
            Save-UninstallCheckpoint -Manifest $manifest
            Complete-ProjectRestoration -Manifest $manifest -Artifact $artifact
            Write-Status '♻️' "Restored previous content to $path (verified completed recovery)."
            continue
        }
        if ($current -and ($artifact.Status -eq 'Restored' -or $current.Kind -ne 'File' -or $current.Hash -ne $artifact.InstalledHash)) {
            Write-Status '⚠️' "$($artifact.Name) has been modified since install; leaving it in place. Recovery: compare with backup at $($artifact.BackupPath)."
            continue
        }
        if ($artifact.BackupPath) {
            if (-not (Get-PathEntry -Path $artifact.BackupPath)) { throw "Original backup is missing for pending recovery of '$path'; state was retained." }
            Restore-ProjectArtifact -Manifest $manifest -Artifact $artifact -CurrentIdentity $current
        }
        else {
            if ($current) { Remove-Item -LiteralPath $path -Force }
            $manifest.Artifacts = @($manifest.Artifacts | Where-Object { $_.Name -cne $artifact.Name })
            Save-UninstallCheckpoint -Manifest $manifest
            Write-Status '✅' "Removed: $path"
        }
    }
    $manifest.RetainedBackups = @($manifest.RetainedBackups | Where-Object { Get-PathEntry -Path $_ })
    Remove-EmptyDirectory -Path (Join-Path $stateDir 'backups')
    $otherState = @(Get-ChildItem -LiteralPath $stateDir -Force | Where-Object { $_.Name -cne 'manifest.json' })
    $needsState = $manifest.Artifacts.Count -gt 0 -or $manifest.RetainedBackups.Count -gt 0 -or $otherState.Count -gt 0
    $localRemains = [bool](Get-PathEntry -Path (Join-Path $instructionsDir 'local-preferences.instructions.md'))
    $removal = $null
    if (-not $needsState -and -not $localRemains) {
        $removal = Get-GitignoreRemoval -TargetPath $TargetPath -Blocks $manifest.GitignoreBlocks
        if (-not $removal.CanRemove) { $needsState = $true }
    }
    if ($needsState) {
        Save-UninstallCheckpoint -Manifest $manifest
        if ($manifest.RetainedBackups.Count -or $otherState.Count) {
            Write-Status '⚠️' "Unconsumed recovery material remains at '$stateDir'. Review it explicitly; no recursive backup cleanup was attempted."
        }
        if ($manifest.GitignorePolicyEnabled) {
            Write-Status 'ℹ️' 'Retained Git exclusions while personal files or installer recovery state remain.'
        }
        else { Write-Status '⚠️' 'Git exclusions were not managed; personal/recovery paths may still be exposed.' }
        Write-Host "`n⚠️  Uninstall finished; some items needed manual attention and were left in place.`n" -ForegroundColor Yellow
        return
    }
    if ($manifest.InstructionsDirCreatedByUs) { Remove-EmptyDirectory -Path $instructionsDir }
    # Remove the last state before its exclusion. A cleanup failure must never expose recovery material.
    Remove-Item -LiteralPath (Get-ManifestPath -TargetPath $TargetPath) -Force
    Assert-DirectoryPath -Path $stateDir
    if (@(Get-ChildItem -LiteralPath $stateDir -Force).Count) { throw "New state appeared during cleanup; retained '$stateDir' and its exclusions." }
    Remove-Item -LiteralPath $stateDir -Force
    if ($localRemains) {
        if ($manifest.GitignorePolicyEnabled) {
            Write-Status 'ℹ️' 'Retained Git exclusions for remaining personal preferences; these rules are no longer installer-owned.'
        }
        else { Write-Status '⚠️' 'Personal preferences remain; Git exclusion management was skipped. Verify protection before storing personal data.' }
    }
    elseif ($removal -and $removal.Changed) {
        Write-BytesAtomically -Path (Join-Path $TargetPath '.gitignore') -Bytes $removal.Bytes
        Write-Status '➖' 'Removed local preferences entry from .gitignore (only complete installer-owned blocks).'
    }
    Write-Host "`n✅ Uninstall complete. Installer state removed.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$templateDir = Join-Path $PSScriptRoot 'templates'
$TargetPath = Get-NormalizedPath -Path $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)

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
