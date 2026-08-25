#Requires -Version 7.0
<#
.SYNOPSIS
    Deterministic, dependency-free regression suite for install.ps1.
.DESCRIPTION
    Invokes install.ps1 out-of-process, always with -TargetRoot pointed at a
    disposable fixture directory under $env:TEMP. Never modifies install.ps1,
    any repo config file, or the real Copilot home (~/.copilot). No Pester,
    no third-party dependency. Mirrors the conventions established by
    tests\ValidateConfig\Run-ValidateConfigTests.ps1.
.EXAMPLE
    pwsh -NoProfile -File .\tests\Install\Run-InstallTests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:TestsPassed = 0
$script:TestsFailed = 0

. (Join-Path $PSScriptRoot 'New-InstallFixture.ps1')

function Write-TestPass {
    param([Parameter(Mandatory)][string]$Name)
    $script:TestsPassed++
    Write-Host "  ✅ $Name" -ForegroundColor Green
}

function Write-TestFail {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Detail
    )
    $script:TestsFailed++
    Write-Host "  ❌ $Name" -ForegroundColor Red
    Write-Host "     $Detail" -ForegroundColor DarkRed
}

function Test-Case {
    <#
    .SYNOPSIS
        Runs one AAA-structured test case with automatic fixture cleanup.
        Arrange may return $null, a fixture-root string, or an object
        exposing a .Root property and/or a .CleanupPaths array (for tests
        that allocate more than one disposable temp directory, e.g. an
        isolated source root plus a target root); whichever is present is
        what gets cleaned up afterwards.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Arrange,
        [Parameter(Mandatory)][scriptblock]$Act,
        [Parameter(Mandatory)][scriptblock]$Assert
    )

    $arranged = $null
    try {
        $arranged = & $Arrange
        $result = & $Act $arranged
        & $Assert $result
        Write-TestPass -Name $Name
    }
    catch {
        Write-TestFail -Name $Name -Detail $_.Exception.Message
    }
    finally {
        $cleanupPaths = @()
        if ($arranged -is [string]) {
            $cleanupPaths = @($arranged)
        }
        elseif ($arranged) {
            $propNames = $arranged.PSObject.Properties.Name
            if ($propNames -contains 'CleanupPaths') { $cleanupPaths += @($arranged.CleanupPaths) }
            elseif ($propNames -contains 'Root') { $cleanupPaths += @($arranged.Root) }
        }

        foreach ($cleanupRoot in $cleanupPaths) {
            if ($cleanupRoot -and (Test-Path -LiteralPath $cleanupRoot -PathType Container)) {
                Remove-FixtureRoot -Path $cleanupRoot
            }
        }
    }
}

Write-Host ''
Write-Host '🔍 Running install.ps1 regression suite...' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Hermeticity baseline: captured BEFORE any test runs, so the guard test at
# the end can prove nothing in this suite ever touched the real Copilot home.
# ---------------------------------------------------------------------------

$script:RealCopilotHome = Join-Path $HOME '.copilot'
$script:RealInstallerDirExisted = Test-Path -LiteralPath (Join-Path $script:RealCopilotHome '.np-copilot-installer')
$script:RealMcpConfigPath = Join-Path $script:RealCopilotHome 'mcp-config.json'
$script:RealMcpConfigHashBefore = $null
if (Test-Path -LiteralPath $script:RealMcpConfigPath -PathType Leaf) {
    $script:RealMcpConfigHashBefore = (Get-FileHash -LiteralPath $script:RealMcpConfigPath -Algorithm SHA256).Hash
}
$script:RealCoreLinkTargetsBefore = @{}
foreach ($linkName in $script:CoreLinkNames) {
    $p = Join-Path $script:RealCopilotHome $linkName
    $script:RealCoreLinkTargetsBefore[$linkName] = $null
    if (Test-Path -LiteralPath $p) {
        $item = Get-Item -LiteralPath $p -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $script:RealCoreLinkTargetsBefore[$linkName] = Resolve-TestLinkTarget $item
        }
    }
}

# ---------------------------------------------------------------------------
# Fresh core install
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_CreateAllFourCoreSymlinks_When_TargetIsEmptyAndNoSwitchesGiven' `
    -Arrange { New-FixtureRoot } `
    -Act { param($root) [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root); Root = $root } } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Installing complete.')) {
            throw "expected the install-complete banner. Output: $($ctx.Result.Output)"
        }
        foreach ($name in $script:CoreLinkNames) {
            $expectedTarget = Get-RepoSourcePath $name
            if (-not (Test-IsSymlinkTo -Path (Join-Path $ctx.Root $name) -ExpectedTarget $expectedTarget)) {
                throw "expected '$name' to be a symlink to $expectedTarget"
            }
        }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root 'mcp-config.json')) {
            throw "mcp-config.json must not be installed without -Mcp"
        }
        $manifest = Import-Manifest -TargetRoot $ctx.Root
        if (-not $manifest) { throw "expected a manifest.json to be written" }
        if ($manifest.McpInstalled) { throw "manifest must record McpInstalled = false for a core-only install" }
        if (@($manifest.Artifacts).Count -ne 4) { throw "expected exactly 4 artifacts in the manifest, got $(@($manifest.Artifacts).Count)" }
    }

# ---------------------------------------------------------------------------
# -WhatIf makes no changes
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_MakeNoChanges_When_WhatIfIsSpecified' `
    -Arrange { New-FixtureRoot } `
    -Act { param($root) [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root -ExtraArgs @('-WhatIf')); Root = $root } } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('WhatIf: no changes were made.')) {
            throw "expected the WhatIf no-op banner. Output: $($ctx.Result.Output)"
        }
        foreach ($name in $script:CoreLinkNames) {
            if (Test-Path -LiteralPath (Join-Path $ctx.Root $name)) { throw "'$name' must not exist after a -WhatIf run" }
        }
        if (Test-Path -LiteralPath (Get-ManifestPath -TargetRoot $ctx.Root)) { throw "no manifest should be written under -WhatIf" }
    }

# ---------------------------------------------------------------------------
# Idempotent re-install
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_ReportAlreadyLinkedAndPreserveCreatedAt_When_RunTwiceWithNoDrift' `
    -Arrange {
        $root = New-FixtureRoot
        Invoke-Install -TargetRoot $root | Out-Null
        $firstManifest = Import-Manifest -TargetRoot $root
        [pscustomobject]@{ Root = $root; FirstCreatedAt = $firstManifest.CreatedAt; FirstUpdatedAt = $firstManifest.UpdatedAt }
    } `
    -Act {
        param($arranged)
        Start-Sleep -Milliseconds 50
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $arranged.Root); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        foreach ($name in $script:CoreLinkNames) {
            if ($ctx.Result.Output -notmatch [regex]::Escape("$name already linked.")) {
                throw "expected '$name already linked.' on the second run. Output: $($ctx.Result.Output)"
            }
        }
        $secondManifest = Import-Manifest -TargetRoot $ctx.Arranged.Root
        if ($secondManifest.CreatedAt -ne $ctx.Arranged.FirstCreatedAt) {
            throw "CreatedAt must be preserved across a no-drift re-install"
        }
        if ($secondManifest.UpdatedAt -eq $ctx.Arranged.FirstUpdatedAt) {
            throw "UpdatedAt must advance on every run, including a no-op re-install"
        }
    }

# ---------------------------------------------------------------------------
# Status redaction
# ---------------------------------------------------------------------------

Test-Case -Name 'Status_Should_RedactSecretsAndUserServerNames_When_McpConfigIsMerged' `
    -Arrange {
        $root = New-FixtureRoot
        $secretValue = 'sk-test-secret-99999-ABCDE'
        $userServerName = 'myCustomUserServer'
        $userConfig = [ordered]@{
            mcpServers = [ordered]@{
                $userServerName = [ordered]@{ type = 'local'; command = 'node'; args = @('server.js'); env = [ordered]@{ TOKEN = $secretValue } }
            }
        }
        ($userConfig | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Encoding utf8 -NoNewline
        Invoke-Install -TargetRoot $root -ExtraArgs @('-Mcp') | Out-Null
        [pscustomobject]@{ Root = $root; Secret = $secretValue; UserServerName = $userServerName }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Status')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -match [regex]::Escape($ctx.Arranged.Secret)) {
            throw "status output must never contain a raw MCP secret value. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -match [regex]::Escape($ctx.Arranged.UserServerName)) {
            throw "status output must never name a user-owned (non-repo) MCP server entry. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('mcp-config.json: Managed (merged file)')) {
            throw "expected a clean 'Managed (merged file)' health line with zero conflicts. Output: $($ctx.Result.Output)"
        }
        foreach ($name in (Get-RepoMcpServerNames)) {
            if ($ctx.Result.Output -notmatch [regex]::Escape("$($name): Managed")) {
                throw "expected a redacted per-entry 'Managed' status line for repo-owned server '$name'. Output: $($ctx.Result.Output)"
            }
        }
    }

# ---------------------------------------------------------------------------
# Safe uninstall
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_RemoveAllManagedArtifactsAndInstallerState_When_NothingDrifted' `
    -Arrange {
        $root = New-FixtureRoot
        Invoke-Install -TargetRoot $root | Out-Null
        $root
    } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root -ExtraArgs @('-Uninstall')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Uninstall complete. Installer state removed.')) {
            throw "expected the clean uninstall-complete banner. Output: $($ctx.Result.Output)"
        }
        foreach ($name in $script:CoreLinkNames) {
            if (Test-Path -LiteralPath (Join-Path $ctx.Root $name)) { throw "'$name' should have been removed by -Uninstall" }
        }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.np-copilot-installer')) {
            throw "installer state directory should be removed after a clean uninstall"
        }
    }

# ---------------------------------------------------------------------------
# Invalid JSON preflight: no mutation anywhere
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_MakeNoMutationAnywhere_When_ExistingMcpConfigIsInvalidJson' `
    -Arrange {
        $root = New-FixtureRoot
        $invalidContent = '{ this is not json'
        Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Value $invalidContent -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; OriginalContent = $invalidContent }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Mcp')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit when preflight detects invalid JSON" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Preflight failed')) {
            throw "expected a preflight-failed message. Output: $($ctx.Result.Output)"
        }
        foreach ($name in $script:CoreLinkNames) {
            if (Test-Path -LiteralPath (Join-Path $ctx.Arranged.Root $name)) {
                throw "'$name' must not be created when preflight fails atomically"
            }
        }
        if (Test-Path -LiteralPath (Get-ManifestPath -TargetRoot $ctx.Arranged.Root)) {
            throw "no manifest should be written when preflight fails"
        }
        $actualContent = Get-Content -LiteralPath (Join-Path $ctx.Arranged.Root 'mcp-config.json') -Raw
        if ($actualContent -ne $ctx.Arranged.OriginalContent) {
            throw "the invalid mcp-config.json must be left byte-for-byte unchanged"
        }
    }

# ---------------------------------------------------------------------------
# Parameter-set conflicts
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_FailFastWithNoMutation_When_McpAndUninstallAreBothSpecified' `
    -Arrange { New-FixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root -ExtraArgs @('-Mcp', '-Uninstall')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit for a conflicting parameter-set combination" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Parameter set cannot be resolved')) {
            throw "expected a parameter-set resolution error. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Get-ManifestPath -TargetRoot $ctx.Root)) {
            throw "no manifest should be written when the parameter set itself is invalid"
        }
    }

Test-Case -Name 'Install_Should_FailFastWithNoMutation_When_StatusAndRepairAreBothSpecified' `
    -Arrange { New-FixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root -ExtraArgs @('-Status', '-Repair')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit for a conflicting parameter-set combination" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Parameter set cannot be resolved')) {
            throw "expected a parameter-set resolution error. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Get-ManifestPath -TargetRoot $ctx.Root)) {
            throw "no manifest should be written when the parameter set itself is invalid"
        }
    }

# ---------------------------------------------------------------------------
# Core drift + Repair
# ---------------------------------------------------------------------------

Test-Case -Name 'Repair_Should_FixOnlyTheDriftedCoreLink_When_OneLinkWasReplacedWithARealDirectory' `
    -Arrange {
        $root = New-FixtureRoot
        Invoke-Install -TargetRoot $root | Out-Null

        $instructionsPath = Join-Path $root 'instructions'
        (Get-Item -LiteralPath $instructionsPath -Force).Delete()
        New-Item -ItemType Directory -Path $instructionsPath | Out-Null
        Set-Content -LiteralPath (Join-Path $instructionsPath 'marker.txt') -Value 'user data' -Encoding utf8
        $root
    } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $root -ExtraArgs @('-Repair')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if (-not (Test-IsSymlinkTo -Path (Join-Path $ctx.Root 'instructions') -ExpectedTarget (Get-RepoSourcePath 'instructions'))) {
            throw "expected the drifted 'instructions' link to be repaired back to a correct symlink"
        }
        foreach ($name in @('copilot-instructions.md', 'agents', 'skills')) {
            if ($ctx.Result.Output -notmatch [regex]::Escape("$name already linked.")) {
                throw "expected the untouched core link '$name' to report already linked, not be re-backed-up. Output: $($ctx.Result.Output)"
            }
        }
        $backupsDir = Join-Path $ctx.Root '.np-copilot-installer\backups'
        $markerBackup = Get-ChildItem -LiteralPath $backupsDir -Recurse -Filter 'marker.txt' -ErrorAction SilentlyContinue
        if (-not $markerBackup) {
            throw "expected the drifted directory's content to be preserved under a timestamped backup, not discarded"
        }
    }

# ---------------------------------------------------------------------------
# MCP regular-file merge preserving a user server
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_PreserveUserOwnedMcpServer_When_MergingIntoARegularMcpConfigFile' `
    -Arrange {
        $root = New-FixtureRoot
        $userServerName = 'myCustomUserServer'
        $userConfig = [ordered]@{
            mcpServers = [ordered]@{
                $userServerName = [ordered]@{ type = 'local'; command = 'python'; args = @('user_server.py') }
            }
        }
        ($userConfig | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; UserServerName = $userServerName }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Mcp')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }

        $mergedRaw = Get-Content -LiteralPath (Join-Path $ctx.Arranged.Root 'mcp-config.json') -Raw
        $merged = $mergedRaw | ConvertFrom-Json
        $userProp = $merged.mcpServers.PSObject.Properties[$ctx.Arranged.UserServerName]
        if (-not $userProp) { throw "the user-owned MCP server entry must survive the merge" }
        if ($userProp.Value.command -ne 'python') { throw "the user-owned MCP server entry must be left byte-for-byte unmodified" }

        $repoNames = Get-RepoMcpServerNames
        foreach ($name in $repoNames) {
            if (-not $merged.mcpServers.PSObject.Properties[$name]) { throw "expected repo-owned MCP server '$name' to be merged in" }
        }

        $manifest = Import-Manifest -TargetRoot $ctx.Arranged.Root
        $mcpArtifact = @($manifest.Artifacts) | Where-Object { $_.Name -eq 'mcp-config.json' } | Select-Object -First 1
        if (-not $mcpArtifact) { throw "expected a mcp-config.json artifact recorded in the manifest" }

        $ownedNames = @($mcpArtifact.OwnedEntries.PSObject.Properties.Name)
        if ($ownedNames -contains $ctx.Arranged.UserServerName) {
            throw "the user-owned entry must never be recorded as repo-owned in the manifest"
        }
        foreach ($name in $repoNames) {
            if ($ownedNames -notcontains $name) { throw "expected '$name' to be recorded as repo-owned in the manifest" }
        }

        $conflictCount = @($mcpArtifact.EntryStatus.PSObject.Properties | Where-Object { $_.Value -eq 'Conflict' }).Count
        if ($conflictCount -ne 0) { throw "expected zero conflicts merging into a config with no prior repo ownership" }
    }

# ---------------------------------------------------------------------------
# MCP three-way merge: Updated branch (owned entry unchanged since last
# install, but the tracked source revised it -> safe to refresh).
#
# install.ps1 resolves its own source as $PSScriptRoot, so there is no
# parameter seam for varying source content the way -TargetRoot is a seam
# for the target. Simulating a tracked source revision therefore runs an
# unmodified *copy* of install.ps1 from an isolated temp source root (see
# New-IsolatedSourceRoot) whose own copy of mcp-config.json this test
# freely mutates. The real repository's install.ps1 and mcp-config.json
# are only ever read (Copy-Item out), never written to.
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_RefreshOwnedEntry_When_TrackedSourceRevisesItAndTargetIsUnchangedSinceLastInstall' `
    -Arrange {
        $isolatedSource = New-IsolatedSourceRoot
        $isolatedInstallScript = Join-Path $isolatedSource 'install.ps1'
        $target = New-FixtureRoot

        # Pre-seed an empty regular (non-symlink) target config so the very
        # first -Mcp run goes through the merge path (Sync-McpEntries) and
        # records real per-entry ownership hashes, rather than short-circuiting
        # into a plain symlink.
        Set-Content -LiteralPath (Join-Path $target 'mcp-config.json') -Value '{"mcpServers": {}}' -Encoding utf8 -NoNewline
        Invoke-Install -TargetRoot $target -ExtraArgs @('-Mcp') -InstallScriptPath $isolatedInstallScript | Out-Null

        # Simulate a tracked source revision: mutate ONLY the isolated copy's
        # mcp-config.json, adding a distinguishing marker to one entry.
        $isolatedMcpPath = Join-Path $isolatedSource 'mcp-config.json'
        $entryName = (Get-McpServerNames -Path $isolatedMcpPath) | Select-Object -First 1
        $revisionMarker = "REVISED-$([guid]::NewGuid())"

        $sourceJson = Get-Content -LiteralPath $isolatedMcpPath -Raw -Encoding utf8 | ConvertFrom-Json
        $entryObj = $sourceJson.mcpServers.$entryName
        $entryObj | Add-Member -NotePropertyName 'xTestRevisionMarker' -NotePropertyValue $revisionMarker -Force
        $sourceJson.mcpServers.$entryName = $entryObj
        ($sourceJson | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $isolatedMcpPath -Encoding utf8 -NoNewline

        [pscustomobject]@{
            CleanupPaths        = @($isolatedSource, $target)
            IsolatedInstallScript = $isolatedInstallScript
            Target              = $target
            EntryName           = $entryName
            RevisionMarker      = $revisionMarker
        }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{
            Result = (Invoke-Install -TargetRoot $arranged.Target -ExtraArgs @('-Mcp') -InstallScriptPath $arranged.IsolatedInstallScript)
            Arranged = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Refreshed unchanged owned MCP servers')) {
            throw "expected the Updated-branch refresh message. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape($ctx.Arranged.EntryName)) {
            throw "expected the refresh message to name the revised entry '$($ctx.Arranged.EntryName)'. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -match [regex]::Escape('conflict')) {
            throw "a same-owner source revision must refresh cleanly, never be reported as a conflict. Output: $($ctx.Result.Output)"
        }

        $mergedRaw = Get-Content -LiteralPath (Join-Path $ctx.Arranged.Target 'mcp-config.json') -Raw
        $merged = $mergedRaw | ConvertFrom-Json
        $mergedEntry = $merged.mcpServers.$($ctx.Arranged.EntryName)
        if ($mergedEntry.xTestRevisionMarker -ne $ctx.Arranged.RevisionMarker) {
            throw "expected the target's owned entry to be refreshed to the revised source value"
        }

        $manifest = Import-Manifest -TargetRoot $ctx.Arranged.Target
        $mcpArtifact = @($manifest.Artifacts) | Where-Object { $_.Name -eq 'mcp-config.json' } | Select-Object -First 1
        if (-not $mcpArtifact) { throw "expected a mcp-config.json artifact recorded in the manifest" }
        if ($mcpArtifact.EntryStatus.$($ctx.Arranged.EntryName) -ne 'Managed') {
            throw "expected the refreshed entry's status to be 'Managed', not a conflict"
        }
    }

# ---------------------------------------------------------------------------
# MCP three-way merge: Conflict branch (user hand-edits a repo-owned target
# entry -> preserved as-is and reported as a conflict, without leaking its
# body or any secret it contains).
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_PreserveAndReportConflict_When_UserModifiesARepoOwnedTargetEntry' `
    -Arrange {
        $root = New-FixtureRoot
        $secretValue = 'sk-conflict-secret-77777-ZZZZZ'

        # Seed a pre-existing regular mcp-config.json containing only a user
        # server, so the first -Mcp run merges (rather than symlinks) and
        # records real ownership hashes for the repo's own entries.
        $seed = [ordered]@{ mcpServers = [ordered]@{ someUnrelatedUserServer = [ordered]@{ type = 'local'; command = 'node'; args = @('x.js') } } }
        ($seed | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Encoding utf8 -NoNewline
        Invoke-Install -TargetRoot $root -ExtraArgs @('-Mcp') | Out-Null

        $repoNames = Get-RepoMcpServerNames
        $entryName = $repoNames | Select-Object -First 1

        # Simulate a user hand-editing a repo-owned target entry after
        # install, embedding a secret so the redaction guarantee is
        # exercised alongside the conflict-preservation guarantee.
        $targetJson = Get-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $entryObj = $targetJson.mcpServers.$entryName
        $entryObj | Add-Member -NotePropertyName 'userAddedSecret' -NotePropertyValue $secretValue -Force
        $targetJson.mcpServers.$entryName = $entryObj
        ($targetJson | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Encoding utf8 -NoNewline

        [pscustomobject]@{ Root = $root; EntryName = $entryName; Secret = $secretValue }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{
            InstallResult = (Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Mcp'))
            StatusResult  = (Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Status'))
            Arranged      = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.InstallResult.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.InstallResult.ExitCode). Output: $($ctx.InstallResult.Output)" }
        if ($ctx.InstallResult.Output -notmatch [regex]::Escape('Preserved MCP servers with a conflict')) {
            throw "expected the conflict-preservation message. Output: $($ctx.InstallResult.Output)"
        }
        if ($ctx.InstallResult.Output -notmatch [regex]::Escape($ctx.Arranged.EntryName)) {
            throw "expected the conflict message to name '$($ctx.Arranged.EntryName)'. Output: $($ctx.InstallResult.Output)"
        }
        if ($ctx.InstallResult.Output -match [regex]::Escape($ctx.Arranged.Secret)) {
            throw "install output must never leak a user-modified entry's secret value"
        }

        $mergedRaw = Get-Content -LiteralPath (Join-Path $ctx.Arranged.Root 'mcp-config.json') -Raw
        $merged = $mergedRaw | ConvertFrom-Json
        $mergedEntry = $merged.mcpServers.$($ctx.Arranged.EntryName)
        if ($mergedEntry.userAddedSecret -ne $ctx.Arranged.Secret) {
            throw "the user-modified repo-owned entry must be preserved exactly as the user left it, never overwritten"
        }

        $manifest = Import-Manifest -TargetRoot $ctx.Arranged.Root
        $mcpArtifact = @($manifest.Artifacts) | Where-Object { $_.Name -eq 'mcp-config.json' } | Select-Object -First 1
        if (-not $mcpArtifact) { throw "expected a mcp-config.json artifact recorded in the manifest" }
        if ($mcpArtifact.EntryStatus.$($ctx.Arranged.EntryName) -ne 'Conflict') {
            throw "expected the manifest to record the modified entry's status as 'Conflict'"
        }

        if ($ctx.StatusResult.ExitCode -ne 0) { throw "expected -Status to exit 0, got $($ctx.StatusResult.ExitCode). Output: $($ctx.StatusResult.Output)" }
        if ($ctx.StatusResult.Output -match [regex]::Escape($ctx.Arranged.Secret)) {
            throw "status output must never leak a conflicting entry's secret value"
        }
        if ($ctx.StatusResult.Output -notmatch [regex]::Escape('conflict')) {
            throw "expected status output to surface the conflict count without leaking the entry's body. Output: $($ctx.StatusResult.Output)"
        }
        if ($ctx.StatusResult.Output -notmatch [regex]::Escape("$($ctx.Arranged.EntryName): Conflict")) {
            throw "expected a per-entry 'Conflict' status line naming '$($ctx.Arranged.EntryName)'. Output: $($ctx.StatusResult.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Regression: the manifest's MCP restore point must remain the pristine
# pre-install copy across every re-merge, never a snapshot of the file
# taken after it already contains repo-owned entries. A second merge round
# (triggered here by a tracked source revision to an already-owned entry,
# landing in the Updated branch) used to overwrite the stored BackupPath
# with a copy of the already-merged target. If the user later had no
# servers of their own left, uninstalling restored that non-pristine
# backup and repo-owned entries silently reappeared instead of the target
# going back to its true pre-install state.
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_RestoreTrulyPristineMcpConfig_When_ASecondMergeRefreshedAnOwnedEntryFirst' `
    -Arrange {
        $isolatedSource = New-IsolatedSourceRoot
        $isolatedInstallScript = Join-Path $isolatedSource 'install.ps1'
        $target = New-FixtureRoot

        # Pristine pre-install content: no user servers at all, so that once
        # every repo-owned entry is removed on uninstall nothing should
        # remain, and the restored file must equal this exactly.
        $pristineContent = '{"mcpServers": {}}'
        Set-Content -LiteralPath (Join-Path $target 'mcp-config.json') -Value $pristineContent -Encoding utf8 -NoNewline

        # First merge: Added branch, takes the one-and-only pristine backup.
        $firstRun = Invoke-Install -TargetRoot $target -ExtraArgs @('-Mcp') -InstallScriptPath $isolatedInstallScript
        if ($firstRun.ExitCode -ne 0) { throw "arrange: first merge failed. Output: $($firstRun.Output)" }

        # Simulate a tracked source revision to an already-owned entry, so
        # the SECOND merge hits the Updated branch (its own backup-then-write
        # round, on a target that is no longer pristine).
        $isolatedMcpPath = Join-Path $isolatedSource 'mcp-config.json'
        $entryName = (Get-McpServerNames -Path $isolatedMcpPath) | Select-Object -First 1
        $sourceJson = Get-Content -LiteralPath $isolatedMcpPath -Raw -Encoding utf8 | ConvertFrom-Json
        $entryObj = $sourceJson.mcpServers.$entryName
        $entryObj | Add-Member -NotePropertyName 'xTestRevisionMarker' -NotePropertyValue 'second-merge-revision' -Force
        $sourceJson.mcpServers.$entryName = $entryObj
        ($sourceJson | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $isolatedMcpPath -Encoding utf8 -NoNewline

        $secondRun = Invoke-Install -TargetRoot $target -ExtraArgs @('-Mcp') -InstallScriptPath $isolatedInstallScript
        if ($secondRun.ExitCode -ne 0) { throw "arrange: second merge failed. Output: $($secondRun.Output)" }
        if ($secondRun.Output -notmatch [regex]::Escape('Refreshed unchanged owned MCP servers')) {
            throw "arrange: expected the second merge to hit the Updated branch. Output: $($secondRun.Output)"
        }

        [pscustomobject]@{
            CleanupPaths          = @($isolatedSource, $target)
            IsolatedInstallScript = $isolatedInstallScript
            Target                = $target
            PristineContent       = $pristineContent
            RepoNames             = @(Get-McpServerNames -Path $isolatedMcpPath)
        }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{
            Result   = (Invoke-Install -TargetRoot $arranged.Target -ExtraArgs @('-Uninstall') -InstallScriptPath $arranged.IsolatedInstallScript)
            Arranged = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Uninstall complete. Installer state removed.')) {
            throw "expected a fully clean uninstall (no leftover conflicts). Output: $($ctx.Result.Output)"
        }

        $mcpConfigPath = Join-Path $ctx.Arranged.Target 'mcp-config.json'
        if (-not (Test-Path -LiteralPath $mcpConfigPath)) {
            throw "expected mcp-config.json to be restored to its pristine pre-install state, not left absent"
        }

        $restoredContent = Get-Content -LiteralPath $mcpConfigPath -Raw
        if ($restoredContent -ne $ctx.Arranged.PristineContent) {
            throw "expected mcp-config.json to be restored byte-for-byte to its pristine pre-install content ('$($ctx.Arranged.PristineContent)'), got: $restoredContent"
        }

        $restoredJson = $restoredContent | ConvertFrom-Json
        foreach ($name in $ctx.Arranged.RepoNames) {
            if ($restoredJson.mcpServers.PSObject.Properties[$name]) {
                throw "repo-owned MCP server '$name' leaked back into mcp-config.json after uninstall; the restore point was not pristine"
            }
        }
    }

# ---------------------------------------------------------------------------
# Regression: a foreign symlink pre-existing at a core-link path (one this
# installer never created, pointing somewhere outside this repo entirely)
# must be preserved and restored exactly as found, never silently deleted
# as though it were merely a stale link from an earlier run of this same
# installer.
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_RestoreForeignSymlinkUntouched_When_ItPreExistedAtACoreLinkPath' `
    -Arrange {
        $root = New-FixtureRoot
        $foreignTargetDir = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-foreign-target-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $foreignTargetDir | Out-Null
        $markerContent = "foreign-user-data-$([guid]::NewGuid())"
        Set-Content -LiteralPath (Join-Path $foreignTargetDir 'marker.txt') -Value $markerContent -Encoding utf8 -NoNewline

        # A pre-existing symlink at the 'instructions' core-link path,
        # authored by the user (or some other tool) and pointing somewhere
        # entirely outside this repository — not something this installer
        # (or an earlier run of it) could ever have created.
        New-Item -ItemType SymbolicLink -Path (Join-Path $root 'instructions') -Target $foreignTargetDir | Out-Null

        [pscustomobject]@{
            CleanupPaths     = @($root, $foreignTargetDir)
            Root             = $root
            ForeignTargetDir = $foreignTargetDir
            MarkerContent    = $markerContent
        }
    } `
    -Act {
        param($arranged)
        $installResult = Invoke-Install -TargetRoot $arranged.Root

        # Snapshot the post-install, pre-uninstall state now — asserting on
        # live filesystem state after both actions have already run would
        # observe the post-uninstall (restored) state instead.
        $postInstallIsLinkedToRepo = Test-IsSymlinkTo -Path (Join-Path $arranged.Root 'instructions') -ExpectedTarget (Get-RepoSourcePath 'instructions')

        $uninstallResult = Invoke-Install -TargetRoot $arranged.Root -ExtraArgs @('-Uninstall')
        [pscustomobject]@{
            InstallResult             = $installResult
            PostInstallIsLinkedToRepo = $postInstallIsLinkedToRepo
            UninstallResult           = $uninstallResult
            Arranged                  = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.InstallResult.ExitCode -ne 0) {
            throw "expected install exit 0, got $($ctx.InstallResult.ExitCode). Output: $($ctx.InstallResult.Output)"
        }
        if (-not $ctx.PostInstallIsLinkedToRepo) {
            throw "expected 'instructions' to be linked to the repo source after install, replacing the foreign symlink. Output: $($ctx.InstallResult.Output)"
        }

        if ($ctx.UninstallResult.ExitCode -ne 0) {
            throw "expected uninstall exit 0, got $($ctx.UninstallResult.ExitCode). Output: $($ctx.UninstallResult.Output)"
        }
        if ($ctx.UninstallResult.Output -notmatch [regex]::Escape('Uninstall complete. Installer state removed.')) {
            throw "expected a clean uninstall. Output: $($ctx.UninstallResult.Output)"
        }

        $instructionsPath = Join-Path $ctx.Arranged.Root 'instructions'
        if (-not (Test-IsSymlinkTo -Path $instructionsPath -ExpectedTarget $ctx.Arranged.ForeignTargetDir)) {
            throw "expected the pre-existing foreign symlink to be restored exactly as found, pointing back to $($ctx.Arranged.ForeignTargetDir)"
        }

        $restoredMarker = Get-Content -LiteralPath (Join-Path $instructionsPath 'marker.txt') -Raw
        if ($restoredMarker -ne $ctx.Arranged.MarkerContent) {
            throw "expected the foreign symlink's target content to remain reachable and unchanged after restore"
        }
    }

# ---------------------------------------------------------------------------
# Hermeticity guard: this suite must never mutate the real Copilot home.
# ---------------------------------------------------------------------------

Test-Case -Name 'Suite_Should_NeverMutate_RealCopilotHome_AcrossAnyTest' `
    -Arrange { $null } `
    -Act { param($unused) [pscustomobject]@{ ExitCode = 0; Output = '' } } `
    -Assert {
        param($r)
        $installerDirExistsNow = Test-Path -LiteralPath (Join-Path $script:RealCopilotHome '.np-copilot-installer')
        if ($installerDirExistsNow -ne $script:RealInstallerDirExisted) {
            throw "a fixture appears to have leaked an installer manifest into the real Copilot home ($script:RealCopilotHome)"
        }

        if ($script:RealMcpConfigHashBefore) {
            $hashAfter = (Get-FileHash -LiteralPath $script:RealMcpConfigPath -Algorithm SHA256).Hash
            if ($hashAfter -ne $script:RealMcpConfigHashBefore) {
                throw "the real Copilot home's mcp-config.json changed during this test run"
            }
        }

        foreach ($linkName in $script:CoreLinkNames) {
            $expectedTarget = $script:RealCoreLinkTargetsBefore[$linkName]
            if (-not $expectedTarget) { continue }
            $p = Join-Path $script:RealCopilotHome $linkName
            if (-not (Test-IsSymlinkTo -Path $p -ExpectedTarget $expectedTarget)) {
                throw "the real Copilot home's '$linkName' symlink was altered during this test run"
            }
        }
    }

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ''
if ($script:TestsFailed -eq 0) {
    Write-Host "✅ All $script:TestsPassed regression tests passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $script:TestsFailed of $($script:TestsPassed + $script:TestsFailed) regression tests failed." -ForegroundColor Red
exit 1
