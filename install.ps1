#Requires -Version 7.0
<#
.SYNOPSIS
    Transactionally symlinks Copilot CLI global config from this repo into a
    selected Copilot home directory, with recovery-aware
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
    An explicit -TargetRoot overrides COPILOT_HOME, which overrides
    ~/.copilot. Source and target must be separate, unlinked directory
    trees. Invalid or relocated ownership state requires explicit recovery.

.PARAMETER TargetRoot
    Copilot home directory to install into. Defaults to COPILOT_HOME when
    set, otherwise ~/.copilot. Relative paths are normalized before use.

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
    Also useful when managing multiple explicitly selected Copilot homes.
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
    [ValidateNotNullOrEmpty()]
    [string]$TargetRoot = $(if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) { Join-Path $HOME '.copilot' } else { $env:COPILOT_HOME }),

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

function Get-InstallItem {
    param([Parameter(Mandatory)][string]$Path)
    try { Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
}

function Get-NormalizedInstallPath {
    param([Parameter(Mandatory)][string]$Path)
    $provider = $null
    $drive = $null
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw 'Installer paths must use the FileSystem provider.' }
    [System.IO.Path]::TrimEndingDirectorySeparator([System.IO.Path]::GetFullPath($resolved))
}

function Assert-UnlinkedDirectoryChain {
    param([Parameter(Mandatory)][string]$Path)
    $current = Get-NormalizedInstallPath $Path
    while ($current) {
        $item = Get-InstallItem $current
        if ($item -and (-not $item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint))) {
            throw "Installer directory ancestry must contain only ordinary directories: $current"
        }
        $parent = Split-Path -Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-BackupHistory {
    param($Artifact)
    if ($Artifact -and $Artifact.BackupHistory) { @($Artifact.BackupHistory) }
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
    return [System.IO.Path]::GetFullPath((Join-Path (Split-Path $Item.FullName -Parent) $rawTarget))
}

function Test-PathIsUnderRoot {
    <#
    .SYNOPSIS
        Returns $true if Path is Root itself, or nested under it.
    .DESCRIPTION
        Lexical containment only. Directory ancestry is checked separately;
        containment never establishes ownership of a symlink.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $sep = [System.IO.Path]::DirectorySeparatorChar
    $altSep = [System.IO.Path]::AltDirectorySeparatorChar
    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($sep, $altSep)
    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($sep, $altSep)

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($normalizedPath.Equals($normalizedRoot, $comparison)) { return $true }
    return $normalizedPath.StartsWith($normalizedRoot + $sep, $comparison)
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

function ConvertFrom-McpJsonElement {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $values = [pscustomobject]@{}
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($property in $Element.EnumerateObject()) {
                if (-not $names.Add($property.Name)) { throw 'Duplicate or case-ambiguous JSON object keys are not supported.' }
                $value = ConvertFrom-McpJsonElement $property.Value
                $values.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($property.Name, $value))
            }
            return $values
        }
        'Array' {
            $values = [System.Collections.Generic.List[object]]::new()
            foreach ($elementValue in $Element.EnumerateArray()) { $values.Add((ConvertFrom-McpJsonElement $elementValue)) }
            return ,$values.ToArray()
        }
        'String' { return $Element.GetString() }
        'Number' { return $Element.Clone() }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { throw 'Unsupported JSON value.' }
    }
}

function Read-McpJson {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 100
        $document = [System.Text.Json.JsonDocument]::Parse($raw, $options)
        try { $json = ConvertFrom-McpJsonElement $document.RootElement }
        finally { $document.Dispose() }
    }
    catch { throw "Cannot read supported MCP JSON at $Path (strict JSON, unique case-insensitive keys, maximum depth 100). Contents have not been printed." }
    if ($json -isnot [System.Management.Automation.PSCustomObject]) {
        throw "MCP configuration must be a JSON object: $Path"
    }
    $servers = $json.PSObject.Properties['mcpServers']
    if ($servers -and $servers.Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw "mcpServers must be a JSON object: $Path"
    }
    if ($servers) {
        foreach ($entry in $servers.Value.PSObject.Properties) {
            if ($entry.Value -isnot [System.Management.Automation.PSCustomObject]) {
                throw "Every MCP server definition must be a JSON object: $Path"
            }
        }
    }
    return $json
}

function ConvertTo-McpJsonText {
    param([Parameter(Mandatory)]$Value)
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 100
    $document = [System.Text.Json.JsonDocument]::Parse((ConvertTo-CanonicalJson $Value), $options)
    try {
        $format = [System.Text.Json.JsonSerializerOptions]::new()
        $format.MaxDepth = 100
        $format.WriteIndented = $true
        [System.Text.Json.JsonSerializer]::Serialize($document.RootElement, [System.Text.Json.JsonElement], $format)
    }
    finally { $document.Dispose() }
}

function Test-JsonFile {
    <#
    .SYNOPSIS
        Reports whether the MCP document has the supported object shape.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        Read-McpJson $Path | Out-Null
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
    if ($InputObject -is [System.Text.Json.JsonElement]) { return $InputObject.GetRawText() }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $parts = foreach ($p in ($InputObject.PSObject.Properties | Sort-Object Name)) {
            '{0}:{1}' -f (ConvertTo-Json -InputObject $p.Name -Compress), (ConvertTo-CanonicalJson $p.Value)
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $parts = foreach ($k in ($InputObject.Keys | Sort-Object)) {
            '{0}:{1}' -f (ConvertTo-Json -InputObject ([string]$k) -Compress), (ConvertTo-CanonicalJson $InputObject[$k])
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
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { -join ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $algorithm.Dispose() }
}

function Get-EntryHash {
    param($Value)
    Get-Sha256Hex -Text (ConvertTo-CanonicalJson $Value)
}

function Get-ArtifactFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    $records = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Path)
    while ($pending.Count) {
        $item = Get-InstallItem $pending.Pop()
        if (-not $item) { throw 'A recovery input disappeared while its identity was being recorded.' }
        $relative = [System.IO.Path]::GetRelativePath($Path, $item.FullName)
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $records.Add([ordered]@{ Path = $relative; Kind = $item.LinkType; Target = @($item.Target) })
        }
        elseif ($item.PSIsContainer) {
            $records.Add([ordered]@{ Path = $relative; Kind = 'Directory' })
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) { $pending.Push($child.FullName) }
        }
        else {
            $records.Add([ordered]@{ Path = $relative; Kind = 'File'; Hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash })
        }
    }
    Get-EntryHash @($records | Sort-Object { $_.Path })
}

function New-TransactionDirectory {
    param([Parameter(Mandatory)][string]$Path)
    Assert-UnlinkedDirectoryChain $Path
    $missing = [System.Collections.Generic.Stack[string]]::new()
    $current = $Path
    while (-not (Get-InstallItem $current)) {
        $missing.Push($current)
        $current = Split-Path $current -Parent
    }
    while ($missing.Count) {
        $directory = $missing.Pop()
        New-Item -ItemType Directory -Path $directory | Out-Null
        if ($null -ne $script:TxLog) { $script:TxLog.Add(@{ Action = 'CreatedDirectory'; Path = $directory }) }
    }
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

function Import-InstallManifest {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$TargetRoot,
        [string]$ExpectedSourceRoot
    )

    Assert-UnlinkedDirectoryChain (Split-Path $ManifestPath -Parent)
    $item = Get-InstallItem $ManifestPath
    if (-not $item) { return $null }
    if ($item.PSIsContainer -or $item.LinkType) { throw "Installer manifest must be an ordinary file: $ManifestPath" }
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Cannot read installer manifest at $ManifestPath. Preserve this state and its backups; recover the manifest before retrying."
    }
    if ($manifest -isnot [System.Management.Automation.PSCustomObject] -or
        $manifest.SchemaVersion -notin @(1, 2) -or $manifest.Artifacts -isnot [array]) {
        throw "Unsupported or invalid installer manifest at $ManifestPath. No ownership will be inferred."
    }
    foreach ($property in @('TargetRoot', 'SourceRoot')) {
        if ($manifest.$property -isnot [string] -or -not [System.IO.Path]::IsPathFullyQualified($manifest.$property)) {
            throw "Manifest $property must be an absolute path; relocated or relative state requires explicit recovery."
        }
    }
    if ((Get-NormalizedInstallPath $manifest.TargetRoot) -ne $TargetRoot) {
        throw 'Manifest target does not match the requested target. Copied or relocated state must be recovered explicitly.'
    }
    if ($ExpectedSourceRoot -and (Get-NormalizedInstallPath $manifest.SourceRoot) -ne $ExpectedSourceRoot) {
        throw 'Manifest source changed. Uninstall the recorded installation before installing from a relocated source.'
    }
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allowedNames = @('copilot-instructions.md', 'instructions', 'agents', 'skills', 'mcp-config.json')
    $backupsRoot = Join-Path (Split-Path $ManifestPath -Parent) 'backups'
    $recoveryPaths = @()
    foreach ($artifact in $manifest.Artifacts) {
        foreach ($property in @('Name', 'Kind', 'TargetPath', 'SourcePath', 'BackupPath', 'OwnedEntries', 'EntryStatus')) {
            if (-not $artifact.PSObject.Properties[$property]) { throw "Manifest artifact is missing $property." }
        }
        if ($artifact.Name -cnotin $allowedNames -or -not $names.Add($artifact.Name) -or
            $artifact.Kind -notin @('CoreLink', 'McpLink', 'McpMerge') -or
            (($artifact.Name -eq 'mcp-config.json') -ne ($artifact.Kind -in @('McpLink', 'McpMerge')))) {
            throw 'Manifest contains an invalid, duplicate, or mismatched artifact record.'
        }
        foreach ($property in @('TargetPath', 'SourcePath')) {
            $root = if ($property -eq 'TargetPath') { $TargetRoot } else { $manifest.SourceRoot }
            if ($artifact.$property -isnot [string] -or -not [System.IO.Path]::IsPathFullyQualified($artifact.$property) -or
                (Get-NormalizedInstallPath $artifact.$property) -ne (Join-Path $root $artifact.Name)) {
                throw "Manifest artifact $property is outside its declared location."
            }
        }
        foreach ($property in @('OwnedEntries', 'EntryStatus')) {
            if ($artifact.$property -isnot [System.Management.Automation.PSCustomObject]) {
                throw "Manifest $property must be an object."
            }
        }
        foreach ($hash in $artifact.OwnedEntries.PSObject.Properties) {
            if ($hash.Value -isnot [string] -or $hash.Value -notmatch '^[0-9a-fA-F]{64}$') { throw 'Manifest ownership hash is invalid.' }
        }
        foreach ($status in $artifact.EntryStatus.PSObject.Properties) {
            if ($status.Value -notin @('Managed', 'Conflict')) { throw 'Manifest entry status is invalid.' }
        }
        if ($artifact.UninstallState) {
            if ($artifact.UninstallState -ne 'PendingRestore' -or -not $artifact.BackupPath -or
                $artifact.RestoreHash -isnot [string] -or $artifact.RestoreHash -notmatch '^[0-9a-fA-F]{64}$' -or
                ($null -ne $artifact.RestoreTargetHash -and
                    ($artifact.RestoreTargetHash -isnot [string] -or $artifact.RestoreTargetHash -notmatch '^[0-9a-fA-F]{64}$'))) {
                throw 'Invalid uninstall recovery journal.'
            }
            if ($ExpectedSourceRoot) { throw 'Uninstall recovery is pending. Resume -Uninstall before installing or repairing.' }
        }
        if ($artifact.PSObject.Properties['BackupHistory'] -and $artifact.BackupHistory -isnot [array]) {
            throw 'Manifest backup history must be an array.'
        }
        foreach ($path in @($artifact.BackupPath) + @(Get-BackupHistory $artifact)) {
            if ($path -and (Split-Path $path -Leaf) -cne $artifact.Name) {
                throw 'Manifest backup does not belong to its declared artifact.'
            }
        }
        if ($artifact.BackupPath) { $recoveryPaths += $artifact.BackupPath }
        $recoveryPaths += @(Get-BackupHistory $artifact)
    }
    if ($manifest.PSObject.Properties['RecoveryPaths'] -and $manifest.RecoveryPaths -isnot [array]) { throw 'Manifest recovery paths must be an array.' }
    $recoveryPaths += @($manifest.RecoveryPaths | Where-Object { $_ })
    foreach ($path in $recoveryPaths) {
        if ($path -isnot [string] -or -not [System.IO.Path]::IsPathFullyQualified($path) -or
            -not (Test-PathIsUnderRoot -Path $path -Root $backupsRoot) -or
            (Split-Path $path -Leaf) -notin $allowedNames -or
            (Split-Path (Split-Path $path -Parent) -Parent) -ne $backupsRoot) {
            throw 'Manifest backup is outside the owned backup layout. No changes were made.'
        }
        Assert-UnlinkedDirectoryChain (Split-Path $path -Parent)
    }
    foreach ($artifact in $manifest.Artifacts) {
        if (-not $artifact.BackupPath) { continue }
        $backupItem = Get-InstallItem $artifact.BackupPath
        if (-not $backupItem -and $artifact.UninstallState -ne 'PendingRestore') {
            throw 'A recorded restore point is missing. Preserve installer state and recover the backup before retrying.'
        }
        if ($backupItem -and $artifact.Kind -eq 'McpMerge' -and ($backupItem.PSIsContainer -or $backupItem.LinkType)) {
            throw 'MCP restore point is not an ordinary file.'
        }
    }
    if (-not $manifest.PSObject.Properties['RecoveryPaths']) {
        $manifest | Add-Member -NotePropertyName RecoveryPaths -NotePropertyValue @()
    }
    return $manifest
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
            BackupHistory = @(Get-BackupHistory $a)
            OwnedEntries = $a.OwnedEntries
            EntryStatus  = $a.EntryStatus
        }
    }
    $artifactRecords = @($artifactRecords) + @($preserved)

    $mcpInstalled = ($artifactRecords | Where-Object { $_.Name -eq 'mcp-config.json' }).Count -gt 0

    [ordered]@{
        SchemaVersion = 2
        SourceRoot    = $SourceRoot
        TargetRoot    = $TargetRoot
        CreatedAt     = $createdAt
        UpdatedAt     = $nowIso
        McpInstalled  = $mcpInstalled
        Artifacts     = $artifactRecords
        RecoveryPaths = @($ExistingManifest.RecoveryPaths | Where-Object { $_ })
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
    if (-not (Test-Path -LiteralPath $dir)) { New-TransactionDirectory $dir }
    $tempPath = Join-Path $dir ".manifest-$([guid]::NewGuid().ToString('N')).tmp"
    $published = $false
    try {
        ($Manifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempPath -Encoding utf8 -NoNewline
        [System.IO.File]::Move($tempPath, $ManifestPath, $true)
        $published = $true
    }
    finally {
        if (-not $published -and (Test-Path -LiteralPath $tempPath)) {
            try {
                Remove-Item -LiteralPath $tempPath -Force
            }
            catch {
                Write-Status '⚠️' "Could not remove temporary manifest file $tempPath after a failed publish: $($_.Exception.Message)"
            }
        }
    }
}

function Save-Manifest {
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
    $failedRestorePoints = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = $script:TxLog.Count - 1; $i -ge 0; $i--) {
        $entry = $script:TxLog[$i]
        $reverted = $true
        try {
            switch ($entry.Action) {
                'CreatedSymlink' {
                    $item = Get-InstallItem $entry.Path
                    if ($item) {
                        if ($item.LinkType -ne 'SymbolicLink') { throw "Rollback found an unexpected replacement at $($entry.Path)." }
                        $item.Delete()
                    }
                }
                'CreatedDirectory' {
                    if (@(Get-ChildItem -LiteralPath $entry.Path -Force).Count -ne 0) {
                        throw "Rollback retained a nonempty directory: $($entry.Path)"
                    }
                    Remove-Item -LiteralPath $entry.Path -Force
                }
                'MovedToBackup' {
                    if (Get-InstallItem $entry.Path) {
                        throw "Rollback cannot overwrite an unexpected replacement at $($entry.Path). Backup retained."
                    }
                    Move-Item -LiteralPath $entry.BackupPath -Destination $entry.Path -Force
                }
                'WroteFile' {
                    if ($entry.PreviousContentPath) {
                        if (-not (Test-Path -LiteralPath $entry.PreviousContentPath)) { throw 'Rollback restore point is missing; the target was retained.' }
                        Copy-Item -LiteralPath $entry.PreviousContentPath -Destination $entry.Path -Force
                    }
                    else {
                        Remove-Item -LiteralPath $entry.Path -Force -ErrorAction SilentlyContinue
                    }
                }
                'CreatedBackupCopy' {
                    if ($failedRestorePoints.Contains($entry.Path)) {
                        $reverted = $false
                        Write-Status '⚠️' "Rollback recovery copy must be retained: $($entry.Path)"
                    }
                    elseif (Get-InstallItem $entry.Path) { Remove-Item -LiteralPath $entry.Path -Force }
                }
            }
            if ($reverted) { Write-Status '↩️' "Reverted $($entry.Action): $($entry.Path)" }
        }
        catch {
            if ($entry.Action -eq 'WroteFile' -and $entry.PreviousContentPath) {
                [void]$failedRestorePoints.Add($entry.PreviousContentPath)
            }
            Write-Status '❌' "Rollback step failed for $($entry.Path): $($_.Exception.Message)"
        }
    }

    if ($script:RunBackupDir -and (Test-Path -LiteralPath $script:RunBackupDir)) {
        if (@(Get-ChildItem -LiteralPath $script:RunBackupDir -Force).Count -eq 0) {
            Remove-Item -LiteralPath $script:RunBackupDir -Force
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
        [Parameter(Mandatory)][string]$TargetRoot,
        $ExistingManifest
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
                $previous = @($ExistingManifest.Artifacts) | Where-Object Name -eq $link.Name
                if ($existing.PSIsContainer -or $existing.LinkType -eq 'HardLink' -or
                    ($previous.Kind -eq 'McpMerge' -and $existing.LinkType)) {
                    $problems.Add("MCP merge requires an ordinary, unaliased file; replacement links are not owned: $targetPath")
                    continue
                }
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
        Assert-UnlinkedDirectoryChain $BackupDir
        New-TransactionDirectory $BackupDir
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
    $backupHistory = @(Get-BackupHistory $PreviousArtifact)

    $existing = Get-InstallItem $targetPath
    if ($existing) {

        if (($existing.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $existing) -eq $sourcePath)) {
            Write-Status '✅' "$($Link.Name) already linked."
            return [pscustomobject]@{
                Name = $Link.Name; Kind = 'CoreLink'; TargetPath = $targetPath
                SourcePath = $sourcePath; BackupPath = $backupPath; BackupHistory = $backupHistory; OwnedEntries = @{}; EntryStatus = @{}
            }
        }

        if ($backupPath) { $backupHistory += $backupPath }
        $backupPath = New-ArtifactBackup -Path $targetPath -BackupDir $BackupDir
    }

    if ($PSCmdlet.ShouldProcess($targetPath, "Create symlink -> $sourcePath")) {
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
        $script:TxLog.Add(@{ Action = 'CreatedSymlink'; Path = $targetPath })
        Write-Status '✅' "$($Link.Name) -> $sourcePath"
    }

    [pscustomobject]@{
        Name = $Link.Name; Kind = 'CoreLink'; TargetPath = $targetPath
        SourcePath = $sourcePath; BackupPath = $backupPath; BackupHistory = $backupHistory; OwnedEntries = @{}; EntryStatus = @{}
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
    $removed = [System.Collections.Generic.List[string]]::new()
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
        $previousHash = $PreviousOwnedHashes[$entryName]

        if (-not $previousHash) {
            # A same-named entry already exists here that this installer has
            # never recorded owning. Even if its content happens to
            # byte-match our template right now, that coincidence must never
            # silently confer ownership — only an entry we are adding for
            # the first time (above), or one we already track as ours, may
            # become "owned". Otherwise a later -Uninstall could remove an
            # entry the user created independently, just because it happened
            # to match.
            $conflicts.Add($entryName)
            continue
        }

        if ($currentHash -eq $sourceHash) {
            $preserved.Add($entryName)
            $ownedHashes[$entryName] = $sourceHash
            continue
        }

        if ($previousHash -eq $currentHash) {
            # Unchanged since our last install of this entry: safe to refresh.
            $existingProp.Value = $sourceValue
            $updated.Add($entryName)
            $ownedHashes[$entryName] = $sourceHash
            continue
        }

        # Owned by us previously but the user modified it since our last install.
        $conflicts.Add($entryName)
        $ownedHashes[$entryName] = $previousHash
    }

    foreach ($entryName in $PreviousOwnedHashes.Keys) {
        if ($SourceServers.PSObject.Properties[$entryName]) { continue }
        $existingProp = $TargetServersRef.PSObject.Properties[$entryName]
        if (-not $existingProp) { continue }
        if ((Get-EntryHash $existingProp.Value) -eq $PreviousOwnedHashes[$entryName]) {
            $TargetServersRef.PSObject.Properties.Remove($entryName)
            $removed.Add($entryName)
        }
        else {
            $conflicts.Add($entryName)
            $ownedHashes[$entryName] = $PreviousOwnedHashes[$entryName]
        }
    }

    [pscustomobject]@{
        Added = @($added); Updated = @($updated); Removed = @($removed); Preserved = @($preserved); Conflicts = @($conflicts)
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
    $transitionFromLink = $PreviousArtifact -and $PreviousArtifact.Kind -eq 'McpLink'
    $backupHistory = @(Get-BackupHistory $PreviousArtifact)
    $carriedBackupPath = if ($PreviousArtifact -and -not $transitionFromLink) { $PreviousArtifact.BackupPath } else { $null }
    if ($transitionFromLink -and $PreviousArtifact.BackupPath) { $backupHistory += $PreviousArtifact.BackupPath }

    $sourceJson = Read-McpJson $SourcePath
    $targetJson = Read-McpJson $TargetPath

    if ($null -eq $targetJson.mcpServers) {
        $targetJson | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $sourceJson.mcpServers) {
        $sourceJson | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{})
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

    $changed = ($sync.Added.Count -gt 0) -or ($sync.Updated.Count -gt 0) -or ($sync.Removed.Count -gt 0)
    if ($changed -or $transitionFromLink) {
        $runBackupPath = Join-Path $BackupDir (Split-Path $TargetPath -Leaf)
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Back up before MCP merge')) {
            Assert-UnlinkedDirectoryChain $BackupDir
            New-TransactionDirectory $BackupDir
            $script:TxLog.Add(@{ Action = 'CreatedBackupCopy'; Path = $runBackupPath })
            Copy-Item -LiteralPath $TargetPath -Destination $runBackupPath -Force
            Write-Status '📦' "Backed up existing MCP config to: $runBackupPath"
        }

        if (-not $hasPristineBackup) {
            # First backup ever taken for this artifact: the target is still
            # in its pre-install state, so this copy IS the pristine
            # restore point going forward.
            $manifestBackupPath = $runBackupPath
        }

        if ($changed -and $PSCmdlet.ShouldProcess($TargetPath, 'Write merged MCP configuration')) {
            # Register rollback intent BEFORE mutating the file, so a
            # partial/failed Set-Content is still recoverable by
            # Undo-Transaction.
            $script:TxLog.Add(@{ Action = 'WroteFile'; Path = $TargetPath; PreviousContentPath = $runBackupPath })
            (ConvertTo-McpJsonText $targetJson) | Set-Content -LiteralPath $TargetPath -Encoding utf8 -NoNewline
            Write-Status '🔀' "Merged MCP config written to: $TargetPath"
        }
    }

    if ($sync.Added.Count -gt 0) { Write-Status '➕' "Added MCP servers: $($sync.Added -join ', ')" }
    if ($sync.Updated.Count -gt 0) { Write-Status '🔄' "Refreshed unchanged owned MCP servers: $($sync.Updated -join ', ')" }
    if ($sync.Removed.Count -gt 0) { Write-Status '➖' "Removed unchanged retired MCP servers: $($sync.Removed -join ', ')" }
    if ($sync.Conflicts.Count -gt 0) {
        Write-Status '⚠️' "Preserved MCP servers with a conflict (user-modified or not repo-owned): $($sync.Conflicts -join ', ')"
    }
    if (($sync.Added.Count -eq 0) -and ($sync.Updated.Count -eq 0) -and ($sync.Removed.Count -eq 0) -and ($sync.Conflicts.Count -eq 0)) {
        Write-Status '✅' 'mcp-config.json already up to date.'
    }

    $entryStatus = @{}
    foreach ($n in $sync.Added) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Updated) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Preserved) { $entryStatus[$n] = 'Managed' }
    foreach ($n in $sync.Conflicts) { $entryStatus[$n] = 'Conflict' }

    [pscustomobject]@{
        Name = 'mcp-config.json'; Kind = 'McpMerge'; TargetPath = $TargetPath; SourcePath = $SourcePath
        BackupPath = $manifestBackupPath; BackupHistory = $backupHistory
        OwnedEntries = $sync.OwnedHashes; EntryStatus = $entryStatus
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
    $backupHistory = @(Get-BackupHistory $PreviousArtifact)

    $existing = Get-InstallItem $TargetPath
    if ($existing) {
        if ($existing.PSIsContainer -or $existing.LinkType -eq 'HardLink' -or
            ($PreviousArtifact.Kind -eq 'McpMerge' -and $existing.LinkType)) {
            throw 'MCP target topology changed or is not an ordinary mergeable file. Existing content was preserved.'
        }

        if ($existing.LinkType -eq 'SymbolicLink') {
            if ((Resolve-LinkTarget $existing) -eq $SourcePath) {
                Write-Status '✅' 'mcp-config.json already linked.'
                return [pscustomobject]@{
                    Name = 'mcp-config.json'; Kind = 'McpLink'; TargetPath = $TargetPath; SourcePath = $SourcePath
                    BackupPath = $backupPath; BackupHistory = $backupHistory; OwnedEntries = @{}; EntryStatus = @{}
                }
            }

            if ($backupPath) { $backupHistory += $backupPath }
            $backupPath = New-ArtifactBackup -Path $TargetPath -BackupDir $BackupDir
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
        BackupPath = $backupPath; BackupHistory = $backupHistory; OwnedEntries = @{}; EntryStatus = @{}
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

    Test-InstallPreflight -Links $Links -SourceRoot $SourceRoot -TargetRoot $TargetRoot -ExistingManifest $ExistingManifest

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

        if ($WhatIfPreference) {
            Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
            return
        }

        # Manifest publication happens inside this same try so that a failure
        # here (serialization, disk full, locked file) triggers the identical
        # rollback as any other failed link/merge step, rather than leaving
        # already-created symlinks/merges on disk untracked by any manifest.
        $manifest = New-ManifestObject -SourceRoot $SourceRoot -TargetRoot $TargetRoot -RunArtifacts $artifacts -ExistingManifest $ExistingManifest
        Save-Manifest -Manifest $manifest -ManifestPath $ManifestPath
    }
    catch {
        Write-Status '❌' "$verb step failed: $($_.Exception.Message)"
        Undo-Transaction
        throw
    }

    $protectedBackups = @($manifest.Artifacts.BackupPath) + @($manifest.Artifacts.BackupHistory) + @($manifest.RecoveryPaths)
    foreach ($entry in $script:TxLog) {
        if ($entry.Action -eq 'WroteFile' -and $entry.PreviousContentPath -notin $protectedBackups) {
            Remove-Item -LiteralPath $entry.PreviousContentPath -Force
        }
    }
    if ((Test-Path -LiteralPath $backupDir) -and @(Get-ChildItem -LiteralPath $backupDir -Force).Count -eq 0) {
        Remove-Item -LiteralPath $backupDir -Force
    }

    Write-Host "`n✅ $verb complete.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

function Get-LiveMcpState {
    param([Parameter(Mandatory)]$Artifact)
    $item = Get-InstallItem $Artifact.TargetPath
    if (-not $item) { return [pscustomobject]@{ Health = 'Missing'; Entries = @{}; Healthy = $false } }
    if ($item.PSIsContainer -or $item.LinkType) {
        return [pscustomobject]@{ Health = 'Drifted (not the expected regular file)'; Entries = @{}; Healthy = $false }
    }
    try { $json = Read-McpJson $Artifact.TargetPath }
    catch { return [pscustomobject]@{ Health = 'Invalid MCP JSON'; Entries = @{}; Healthy = $false } }
    $entries = @{}
    $names = @($Artifact.EntryStatus.PSObject.Properties.Name) + @($Artifact.OwnedEntries.PSObject.Properties.Name)
    foreach ($name in ($names | Sort-Object -Unique)) {
        $prop = if ($json.mcpServers) { $json.mcpServers.PSObject.Properties[$name] } else { $null }
        $owned = $Artifact.OwnedEntries.PSObject.Properties[$name]
        $entries[$name] = if (-not $prop) { 'Missing' }
        elseif ($owned -and (Get-EntryHash $prop.Value) -eq $owned.Value) { 'Managed' }
        else { 'Conflict' }
    }
    $badCount = @($entries.Values | Where-Object { $_ -ne 'Managed' }).Count
    $health = if ($badCount) { "Managed (merged file) - $badCount conflict(s) or missing entries" } else { 'Managed (merged file)' }
    [pscustomobject]@{ Health = $health; Entries = $entries; Healthy = ($badCount -eq 0) }
}

function Invoke-StatusReport {
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$InstallerDir
    )

    Write-Host "`n📋 Copilot global config status" -ForegroundColor Cyan
    Write-Host "   Target: $TargetRoot`n"

    $manifest = Import-InstallManifest -ManifestPath $ManifestPath -TargetRoot $TargetRoot
    if (-not $manifest) {
        Write-Status 'ℹ️' 'No installation manifest found. Run install.ps1 to install.'
        return
    }

    Write-Status 'ℹ️' "Installed: $($manifest.CreatedAt)  |  Last updated: $($manifest.UpdatedAt)"
    Write-Status 'ℹ️' "MCP tracked: $(@($manifest.Artifacts | Where-Object Name -eq 'mcp-config.json').Count -gt 0)"
    Write-Host ''

    foreach ($artifact in @($manifest.Artifacts)) {
        $targetPath = $artifact.TargetPath
        $health = 'Missing'
        $icon = '❌'

        $liveEntries = @{}
        $item = Get-InstallItem $targetPath
        if ($artifact.UninstallState -eq 'PendingRestore') {
            $health = 'Uninstall restore pending'; $icon = '⚠️'
        }
        elseif ($item) {
            if ($artifact.Kind -in @('CoreLink', 'McpLink')) {
                if (($item.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $item) -eq $artifact.SourcePath)) {
                    $sourceType = if ($artifact.Name -in @('instructions', 'agents', 'skills')) { 'Container' } else { 'Leaf' }
                    if (-not (Test-Path -LiteralPath $artifact.SourcePath -PathType $sourceType)) {
                        $health = 'Missing or invalid source referent'
                    }
                    elseif ($artifact.Kind -eq 'McpLink' -and -not (Test-JsonFile $targetPath)) {
                        $health = 'Invalid MCP JSON'
                    }
                    else { $health = 'OK'; $icon = '✅' }
                }
                else {
                    $health = 'Drifted (not the expected symlink)'; $icon = '⚠️'
                }
            }
            elseif ($artifact.Kind -eq 'McpMerge') {
                $live = Get-LiveMcpState $artifact
                $health = $live.Health
                $icon = if ($live.Healthy) { '✅' } else { '⚠️' }
                $liveEntries = $live.Entries
            }
        }

        Write-Status $icon "$($artifact.Name): $health"

        if ($artifact.Kind -eq 'McpMerge') {
            foreach ($name in ($liveEntries.Keys | Sort-Object)) {
                $entryIcon = if ($liveEntries[$name] -ne 'Managed') { '⚠️' } else { '•' }
                Write-Status "  $entryIcon" "$($name): $($liveEntries[$name])"
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

function Save-UninstallProgress {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )
    $Manifest.McpInstalled = @($Manifest.Artifacts | Where-Object Name -eq 'mcp-config.json').Count -gt 0
    $Manifest.UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
    Save-ManifestFileAtomically -Manifest $Manifest -ManifestPath $ManifestPath
}

function Restore-RecordedArtifact {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )
    if (-not $PSCmdlet.ShouldProcess($Artifact.TargetPath, 'Restore recorded original with durable recovery journal')) { return $false }
    if (-not $Artifact.UninstallState) {
        $restoreHash = Get-ArtifactFingerprint $Artifact.BackupPath
        $targetHash = if (Get-InstallItem $Artifact.TargetPath) { Get-ArtifactFingerprint $Artifact.TargetPath } else { $null }
        $Artifact | Add-Member -NotePropertyName UninstallState -NotePropertyValue 'PendingRestore' -Force
        $Artifact | Add-Member -NotePropertyName RestoreHash -NotePropertyValue $restoreHash -Force
        $Artifact | Add-Member -NotePropertyName RestoreTargetHash -NotePropertyValue $targetHash -Force
        Save-UninstallProgress -Manifest $Manifest -ManifestPath $ManifestPath
    }

    $backup = Get-InstallItem $Artifact.BackupPath
    $targetItem = Get-InstallItem $Artifact.TargetPath
    $targetHash = if ($targetItem) { Get-ArtifactFingerprint $Artifact.TargetPath } else { $null }
    if (-not $backup) {
        if ($targetItem -and $targetHash -eq $Artifact.RestoreHash) { return $true }
        throw "An interrupted restore needs attention at $($Artifact.TargetPath); the recorded original is not identifiable."
    }
    if ((Get-ArtifactFingerprint $Artifact.BackupPath) -ne $Artifact.RestoreHash) {
        throw 'The pending restore point changed. Both target and recovery material were retained.'
    }
    if ($targetItem -and $targetHash -eq $Artifact.RestoreHash) { return $true }
    if ($targetItem -and $targetHash -ne $Artifact.RestoreTargetHash) {
        throw "Target changed during pending restoration: $($Artifact.TargetPath). It was not overwritten."
    }

    if ($Artifact.Kind -eq 'McpMerge') {
        if ($targetItem -and ($targetItem.PSIsContainer -or $targetItem.LinkType)) {
            throw 'Pending MCP restoration will not replace a foreign link or directory.'
        }
        [System.IO.File]::Move($Artifact.BackupPath, $Artifact.TargetPath, $true)
    }
    else {
        if ($targetItem) {
            if ($targetItem.LinkType -ne 'SymbolicLink' -or (Resolve-LinkTarget $targetItem) -ne $Artifact.SourcePath) {
                throw 'Pending restoration will not replace an unexpected target.'
            }
            $targetItem.Delete()
        }
        $backup.MoveTo($Artifact.TargetPath)
    }
    Write-Status '♻️' "Restored previous item to $($Artifact.TargetPath)"
    return $true
}

function Complete-UninstallArtifact {
    param(
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ManifestPath
    )
    if ($WhatIfPreference) { return }
    $retained = @($Manifest.RecoveryPaths)
    foreach ($path in @($Artifact.BackupPath) + @(Get-BackupHistory $Artifact)) {
        if ($path -and (Get-InstallItem $path)) { $retained += $path }
    }
    $Manifest.RecoveryPaths = @($retained | Select-Object -Unique)
    $Manifest.Artifacts = @($Manifest.Artifacts | Where-Object Name -cne $Artifact.Name)
    Save-UninstallProgress -Manifest $Manifest -ManifestPath $ManifestPath
}

function Remove-OwnedMcpEntries {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Removes a whole collection of owned MCP server entries as a batch; a singular name would misrepresent its contract.')]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)][scriptblock]$RestoreOriginal
    )

    $conflicts = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()

    $item = Get-InstallItem $TargetPath
    if (-not $item -or $item.PSIsContainer -or $item.LinkType) {
        Write-Status '❌' 'MCP target is no longer the ordinary file that was merged. Foreign content was not read or changed.'
        return [pscustomobject]@{ Conflicts = @(); RemainingCount = -1; Restored = $false; OwnedHashes = @{}; Processed = $false }
    }
    try {
        $json = Read-McpJson $TargetPath
    }
    catch {
        Write-Status '❌' "Cannot read valid MCP configuration at $TargetPath during uninstall. Contents were not printed."
        return [pscustomobject]@{ Conflicts = @(); RemainingCount = -1; Restored = $false; OwnedHashes = @{}; Processed = $false }
    }

    $owned = @{}
    if ($Artifact.OwnedEntries) {
        foreach ($p in $Artifact.OwnedEntries.PSObject.Properties) { $owned[$p.Name] = $p.Value }
    }

    foreach ($name in $owned.Keys) {
        $prop = if ($json.mcpServers) { $json.mcpServers.PSObject.Properties[$name] } else { $null }
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

    $restored = $false
    $processed = $true
    $matchesOriginal = $false
    if ($Artifact.BackupPath -and $conflicts.Count -eq 0) {
        $original = Read-McpJson $Artifact.BackupPath
        if (-not $original.PSObject.Properties['mcpServers'] -and $json.mcpServers -and
            @($json.mcpServers.PSObject.Properties).Count -eq 0) {
            $json.PSObject.Properties.Remove('mcpServers')
        }
        $matchesOriginal = (Get-EntryHash $json) -eq (Get-EntryHash $original)
    }
    if ($matchesOriginal) {
        $restored = & $RestoreOriginal $Artifact
        $processed = $restored
    }
    elseif ($removed.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Remove unmodified repo-owned MCP entries')) {
            (ConvertTo-McpJsonText $json) | Set-Content -LiteralPath $TargetPath -Encoding utf8 -NoNewline
            Write-Status '➖' "Removed managed MCP servers: $($removed -join ', ')"
        }
        else { $processed = $false }
    }

    $remainingOwned = @{}
    foreach ($name in $conflicts) { $remainingOwned[$name] = $owned[$name] }
    $remainingCount = if ($json.mcpServers) { @($json.mcpServers.PSObject.Properties).Count } else { 0 }
    [pscustomobject]@{ Conflicts = @($conflicts); RemainingCount = $remainingCount; Restored = $restored; OwnedHashes = $remainingOwned; Processed = $processed }
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

    $manifest = Import-InstallManifest -ManifestPath $ManifestPath -TargetRoot $TargetRoot
    if (-not $manifest) {
        Invoke-LegacyUninstall -TargetRoot $TargetRoot -SourceRoot $SourceRoot
        return
    }

    $remainingArtifacts = [System.Collections.Generic.List[object]]::new()
    if (-not $WhatIfPreference) {
        $probe = [System.IO.File]::Open($ManifestPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
        $probe.Dispose()
    }

    foreach ($artifact in @($manifest.Artifacts)) {
        $targetPath = $artifact.TargetPath
        if ($artifact.UninstallState -eq 'PendingRestore') {
            if (Restore-RecordedArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath) {
                Complete-UninstallArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath
            }
            else { $remainingArtifacts.Add($artifact) }
            continue
        }

        if ($artifact.Kind -in @('CoreLink', 'McpLink')) {
            $item = Get-InstallItem $targetPath
            if (-not $item) {
                Write-Status '⏭️' "$($artifact.Name): already absent."
                if ($artifact.BackupPath -and -not (Restore-RecordedArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath)) {
                    $remainingArtifacts.Add($artifact)
                    continue
                }
                Complete-UninstallArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath
                continue
            }

            if (($item.LinkType -eq 'SymbolicLink') -and ((Resolve-LinkTarget $item) -eq $artifact.SourcePath)) {
                if ($artifact.BackupPath) {
                    if (-not (Restore-RecordedArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath)) {
                        $remainingArtifacts.Add($artifact)
                        continue
                    }
                }
                elseif ($PSCmdlet.ShouldProcess($targetPath, 'Remove managed symlink')) {
                    $item.Delete()
                    Write-Status '✅' "Removed: $targetPath"
                }
                else {
                    $remainingArtifacts.Add($artifact)
                    continue
                }
                Complete-UninstallArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath
            }
            else {
                $remainingArtifacts.Add($artifact)
                Write-Status '⚠️' "$($artifact.Name) changed since install; left in place at $targetPath."
                Write-Host "     Recovery: compare it with $($artifact.SourcePath); remove it manually and re-run -Uninstall to finish, or run -Repair to relink." -ForegroundColor Yellow
            }
        }
        elseif ($artifact.Kind -eq 'McpMerge') {
            if (-not (Get-InstallItem $targetPath)) {
                Write-Status '⏭️' "$($artifact.Name): already absent."
                if ($artifact.BackupPath -and -not (Restore-RecordedArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath)) {
                    $remainingArtifacts.Add($artifact)
                    continue
                }
                Complete-UninstallArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath
                continue
            }

            $result = Remove-OwnedMcpEntries -TargetPath $targetPath -Artifact $artifact -RestoreOriginal {
                param($restoreArtifact)
                Restore-RecordedArtifact -Artifact $restoreArtifact -Manifest $manifest -ManifestPath $ManifestPath
            }
            if (-not $result.Processed -and $result.RemainingCount -ge 0) {
                $remainingArtifacts.Add($artifact)
                continue
            }
            if ($result.RemainingCount -lt 0 -or $result.Conflicts.Count -gt 0) {
                if ($result.RemainingCount -ge 0 -and -not $WhatIfPreference) {
                    $artifact.OwnedEntries = [pscustomobject]@{}
                    $artifact.EntryStatus = [pscustomobject]@{}
                    foreach ($name in $result.Conflicts) {
                        $artifact.OwnedEntries.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($name, $result.OwnedHashes[$name]))
                        $artifact.EntryStatus.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($name, 'Conflict'))
                    }
                }
                $remainingArtifacts.Add($artifact)
                if ($result.Conflicts.Count -gt 0) {
                    Write-Status '⚠️' "mcp-config.json retains user-modified entries: $($result.Conflicts -join ', ')."
                    Write-Host "     Recovery: these were left untouched; edit $targetPath by hand if you no longer want them." -ForegroundColor Yellow
                }
                else {
                    Write-Host "     Recovery: restore an ordinary valid JSON file at $targetPath before retrying; foreign links are not followed." -ForegroundColor Yellow
                }
            }
            else {
                Complete-UninstallArtifact -Artifact $artifact -Manifest $manifest -ManifestPath $ManifestPath
            }
        }
    }

    if ($WhatIfPreference) {
        Write-Host "`nWhatIf: no changes were made.`n" -ForegroundColor Yellow
        return
    }
    $manifest.Artifacts = @($remainingArtifacts)
    $manifest.RecoveryPaths = @($manifest.RecoveryPaths | Where-Object { Get-InstallItem $_ })
    Save-UninstallProgress -Manifest $manifest -ManifestPath $ManifestPath

    if ($remainingArtifacts.Count -gt 0) {
        Write-Host "`nℹ️  Some items needed manual attention (see guidance above). Re-run -Uninstall after resolving them to finish cleanup.`n" -ForegroundColor Yellow
        return
    }
    $backupsDir = Join-Path $InstallerDir 'backups'
    if (Test-Path -LiteralPath $backupsDir) {
        Assert-UnlinkedDirectoryChain $backupsDir
        foreach ($run in @(Get-ChildItem -LiteralPath $backupsDir -Force)) {
            if ($run.PSIsContainer -and -not ($run.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
                @(Get-ChildItem -LiteralPath $run.FullName -Force).Count -eq 0) {
                Remove-Item -LiteralPath $run.FullName -Force
            }
        }
        if (@(Get-ChildItem -LiteralPath $backupsDir -Force).Count -eq 0) {
            Remove-Item -LiteralPath $backupsDir -Force
        }
    }
    $retained = @(Get-ChildItem -LiteralPath $InstallerDir -Force | Where-Object FullName -ne $ManifestPath)
    if ($retained.Count -gt 0) {
        Write-Host "`n✅ Uninstall complete. Recovery backups or unrecognized state retained at $InstallerDir; inspect before removing them.`n" -ForegroundColor Green
    }
    else {
        if ($PSCmdlet.ShouldProcess($InstallerDir, 'Remove empty installer state')) {
            Remove-Item -LiteralPath $ManifestPath -Force
            Remove-Item -LiteralPath $InstallerDir -Force
            if (Get-InstallItem $InstallerDir) { throw 'Installer state cleanup did not complete.' }
            Write-Host "`n✅ Uninstall complete. Installer state removed.`n" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$source = Get-NormalizedInstallPath $PSScriptRoot
$target = Get-NormalizedInstallPath $TargetRoot
Assert-UnlinkedDirectoryChain $target
if ((Test-PathIsUnderRoot $target $source) -or (Test-PathIsUnderRoot $source $target)) {
    throw 'Installer source and target must not overlap.'
}
$installerDir = Join-Path $target '.np-copilot-installer'
$manifestPath = Join-Path $installerDir 'manifest.json'
$script:RunStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N')

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
        $existingManifest = Import-InstallManifest -ManifestPath $manifestPath -TargetRoot $target -ExpectedSourceRoot $source
        if (-not $existingManifest) {
            throw "No installation manifest found at $manifestPath. Run install.ps1 first, then use -Repair."
        }
        $remainingNames = @($existingManifest.Artifacts.Name)
        $links = @($coreLinks | Where-Object { $_.Name -in $remainingNames })
        if ('mcp-config.json' -in $remainingNames) { $links += $mcpLink }
        if ($links.Count -eq 0) {
            Write-Status 'ℹ️' 'No active artifacts remain to repair. Recovery backups have been retained.'
            break
        }
        Invoke-InstallOrRepair -SourceRoot $source -TargetRoot $target -Links $links -InstallerDir $installerDir `
            -ManifestPath $manifestPath -ExistingManifest $existingManifest -IsRepair $true
    }
    default {
        $existingManifest = Import-InstallManifest -ManifestPath $manifestPath -TargetRoot $target -ExpectedSourceRoot $source
        $links = @($coreLinks)
        if ($Mcp) { $links += $mcpLink }
        Invoke-InstallOrRepair -SourceRoot $source -TargetRoot $target -Links $links -InstallerDir $installerDir `
            -ManifestPath $manifestPath -ExistingManifest $existingManifest -IsRepair $false
    }
}
