#Requires -Version 7.0
<#
.SYNOPSIS
    Deterministic, dependency-free regression suite for install-project.ps1.
.DESCRIPTION
    Invokes install-project.ps1 out-of-process, always with -TargetPath
    pointed at a disposable fixture directory under $env:TEMP that has been
    initialized as a real git repository via `git init`. Never modifies
    install-project.ps1, any repo template, or the real Copilot home
    (~/.copilot). No Pester, no third-party dependency. Mirrors the
    conventions established by tests\Install\Run-InstallTests.ps1.
.EXAMPLE
    pwsh -NoProfile -File .\tests\InstallProject\Run-InstallProjectTests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:TestsPassed = 0
$script:TestsFailed = 0

. (Join-Path $PSScriptRoot 'New-InstallProjectFixture.ps1')

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
        exposing a .Root property and/or a .CleanupPaths array; whichever
        is present is what gets cleaned up afterwards.
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
                Remove-ProjectFixtureRoot -Path $cleanupRoot
            }
        }
    }
}

Write-Host ''
Write-Host '🔍 Running install-project.ps1 regression suite...' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Hermeticity baseline: captured BEFORE any test runs, so the guard test at
# the end can prove nothing in this suite ever touched the real repository's
# own working tree/templates, or the real Copilot home.
# ---------------------------------------------------------------------------

$script:RepoTemplatesHashBefore = (Get-ChildItem -LiteralPath $script:TemplatesDir -Recurse -File |
        Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ','
$script:RepoRootStateDirExistedBefore = Test-Path -LiteralPath (Join-Path $script:InstallProjectRepoRoot $script:StateDirName)
$script:RealCopilotHome = Join-Path $HOME '.copilot'
$script:RealCopilotProjectStateDirExistedBefore = Test-Path -LiteralPath (Join-Path $script:RealCopilotHome $script:StateDirName)

# ---------------------------------------------------------------------------
# Fresh install: Generic template
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_InstallGenericArtifactsAndWriteManifest_When_TargetIsFreshGitRepo' `
    -Arrange { New-GitFixtureRoot } `
    -Act { param($root) [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root); Root = $root } } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Project templates installed (template: Generic)')) {
            throw "expected the install-complete banner for the Generic template. Output: $($ctx.Result.Output)"
        }

        $instructionsDir = Get-InstructionsDir -TargetPath $ctx.Root
        $projectConfigPath = Join-Path $instructionsDir 'project-config.instructions.md'
        $localPrefsPath = Join-Path $instructionsDir 'local-preferences.instructions.md'

        if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) { throw "expected project-config.instructions.md to be installed" }
        if (-not (Test-Path -LiteralPath $localPrefsPath -PathType Leaf)) { throw "expected local-preferences.instructions.md to be installed" }

        $expectedProjectConfigHash = Get-Sha256TestFileHash -Path (Get-TemplateSourcePath -Template 'Generic')
        $expectedLocalPrefsHash = Get-Sha256TestFileHash -Path (Get-LocalPreferencesSourcePath)
        if ((Get-Sha256TestFileHash -Path $projectConfigPath) -ne $expectedProjectConfigHash) {
            throw "installed project-config.instructions.md content must byte-match the Generic template"
        }
        if ((Get-Sha256TestFileHash -Path $localPrefsPath) -ne $expectedLocalPrefsHash) {
            throw "installed local-preferences.instructions.md content must byte-match its template"
        }

        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if (-not $manifest) { throw "expected a manifest.json to be written" }
        if ($manifest.Template -ne 'Generic') { throw "expected manifest.Template to be 'Generic', got '$($manifest.Template)'" }
        if (@($manifest.Artifacts).Count -ne 2) { throw "expected exactly 2 artifacts in the manifest, got $(@($manifest.Artifacts).Count)" }
        if (-not $manifest.InstructionsDirCreatedByUs) { throw "expected InstructionsDirCreatedByUs to be true for a fresh install" }
        if (-not $manifest.GitignoreManaged) { throw "expected GitignoreManaged to be true when -SkipGitignore was not specified" }
    }

# ---------------------------------------------------------------------------
# Fresh install: non-default template variant
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_InstallAngularTemplateVariantContent_When_TemplateParameterIsAngular' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Template', 'Angular')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Project templates installed (template: Angular)')) {
            throw "expected the install-complete banner naming the Angular template. Output: $($ctx.Result.Output)"
        }

        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md'
        $expectedHash = Get-Sha256TestFileHash -Path (Get-TemplateSourcePath -Template 'Angular')
        if ((Get-Sha256TestFileHash -Path $projectConfigPath) -ne $expectedHash) {
            throw "installed project-config.instructions.md must byte-match the Angular template variant, not Generic"
        }

        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.Template -ne 'Angular') { throw "expected manifest.Template to be 'Angular', got '$($manifest.Template)'" }
    }

# ---------------------------------------------------------------------------
# Invalid -Template value: rejected before any script logic runs
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_RejectInvalidTemplateValueWithNoMutation_When_TemplateIsNotInValidSet' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Template', 'Foo')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit for an out-of-set -Template value" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('does not belong to the set')) {
            throw "expected a ValidateSet rejection message. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Get-InstructionsDir -TargetPath $ctx.Root)) {
            throw "no instructions directory should be created when parameter validation fails"
        }
    }

# ---------------------------------------------------------------------------
# -WhatIf makes no changes
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_MakeNoFilesystemChanges_When_WhatIfIsSpecified' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-WhatIf')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('WhatIf: no changes were made.')) {
            throw "expected the WhatIf no-op banner. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.github')) { throw "'.github' must not exist after a -WhatIf run" }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.gitignore')) { throw "'.gitignore' must not be created under -WhatIf" }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw "no installer state directory should exist under -WhatIf" }
    }

# ---------------------------------------------------------------------------
# Idempotent re-install
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_ReportUpToDateAndPreserveCreatedAt_When_RunTwiceWithNoDrift' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $firstManifest = Import-ProjectTestManifest -TargetPath $root
        [pscustomobject]@{ Root = $root; FirstCreatedAt = $firstManifest.CreatedAt; FirstUpdatedAt = $firstManifest.UpdatedAt }
    } `
    -Act {
        param($arranged)
        Start-Sleep -Milliseconds 50
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $arranged.Root); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('project-config.instructions.md already up to date.')) {
            throw "expected project-config.instructions.md to be reported already up to date. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('local-preferences.instructions.md already up to date.')) {
            throw "expected local-preferences.instructions.md to be reported already up to date. Output: $($ctx.Result.Output)"
        }

        $secondManifest = Import-ProjectTestManifest -TargetPath $ctx.Arranged.Root
        if ($secondManifest.CreatedAt -ne $ctx.Arranged.FirstCreatedAt) {
            throw "CreatedAt must be preserved across a no-drift re-install"
        }
        if ($secondManifest.UpdatedAt -eq $ctx.Arranged.FirstUpdatedAt) {
            throw "UpdatedAt must advance on every run, including a no-op re-install"
        }
    }

# ---------------------------------------------------------------------------
# User conflict preserved without -Force
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_LeaveUserEditedFileUnchanged_When_ConflictExistsWithoutForce' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        $editedContent = 'MY CUSTOM EDIT - DO NOT OVERWRITE'
        Set-Content -LiteralPath $projectConfigPath -Value $editedContent -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; ProjectConfigPath = $projectConfigPath; EditedContent = $editedContent }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $arranged.Root); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('already exists with different content; leaving as-is')) {
            throw "expected a conflict warning naming the edited file. Output: $($ctx.Result.Output)"
        }

        $actualContent = Get-Content -LiteralPath $ctx.Arranged.ProjectConfigPath -Raw
        if ($actualContent -ne $ctx.Arranged.EditedContent) {
            throw "the user-edited file must be left byte-for-byte unchanged without -Force"
        }

        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Arranged.Root
        $artifact = @($manifest.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        if ($artifact.Status -ne 'Conflict') { throw "expected the manifest artifact status to be 'Conflict', got '$($artifact.Status)'" }
    }

# ---------------------------------------------------------------------------
# -Force overwrites a conflict and backs up the prior content
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_BackUpAndOverwriteConflictingContent_When_ForceIsSpecified' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        $editedContent = 'MY CUSTOM EDIT - SHOULD BE BACKED UP'
        Set-Content -LiteralPath $projectConfigPath -Value $editedContent -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; ProjectConfigPath = $projectConfigPath; EditedContent = $editedContent }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $arranged.Root -ExtraArgs @('-Force')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('overwritten (-Force); previous content backed up')) {
            throw "expected a -Force overwrite confirmation. Output: $($ctx.Result.Output)"
        }

        $expectedTemplateHash = Get-Sha256TestFileHash -Path (Get-TemplateSourcePath -Template 'Generic')
        if ((Get-Sha256TestFileHash -Path $ctx.Arranged.ProjectConfigPath) -ne $expectedTemplateHash) {
            throw "expected the file to be overwritten with the current template content after -Force"
        }

        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Arranged.Root
        $artifact = @($manifest.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        if (-not $artifact.BackupPath) { throw "expected a BackupPath to be recorded for the -Force overwrite" }
        if (-not (Test-Path -LiteralPath $artifact.BackupPath -PathType Leaf)) { throw "expected the backup file to actually exist on disk" }
        if ((Get-Content -LiteralPath $artifact.BackupPath -Raw) -ne $ctx.Arranged.EditedContent) {
            throw "expected the backup to contain the pre-Force user-edited content"
        }
    }

# ---------------------------------------------------------------------------
# Uninstall restores the pre-Force backup content
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_RestorePreForceBackedUpContent_When_UninstallingAfterForceOverwrite' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        $editedContent = 'MY CUSTOM EDIT - SHOULD BE RESTORED BY UNINSTALL'
        Set-Content -LiteralPath $projectConfigPath -Value $editedContent -Encoding utf8 -NoNewline
        Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Force') | Out-Null
        [pscustomobject]@{ Root = $root; ProjectConfigPath = $projectConfigPath; EditedContent = $editedContent }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $arranged.Root -ExtraArgs @('-Uninstall')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Restored previous content to')) {
            throw "expected an uninstall restoration message. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Uninstall complete. Installer state removed.')) {
            throw "expected a clean uninstall-complete banner. Output: $($ctx.Result.Output)"
        }

        if ((Get-Content -LiteralPath $ctx.Arranged.ProjectConfigPath -Raw) -ne $ctx.Arranged.EditedContent) {
            throw "expected the pre-Force user-edited content to be restored after -Uninstall"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Arranged.Root)) {
            throw "installer state directory should be fully removed after a clean uninstall"
        }
    }

# ---------------------------------------------------------------------------
# Managed gitignore block: idempotent append
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_AppendGitignoreBlockExactlyOnce_When_RunTwice' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $root
    } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('.gitignore already contains the local preferences entry.')) {
            throw "expected the second run to recognize the entry already present. Output: $($ctx.Result.Output)"
        }

        $gitignoreContent = Get-Content -LiteralPath (Join-Path $ctx.Root '.gitignore') -Raw
        $occurrences = ([regex]::Matches($gitignoreContent, [regex]::Escape($script:GitignoreEntry))).Count
        if ($occurrences -ne 1) { throw "expected the gitignore entry to appear exactly once, found $occurrences occurrence(s)" }
        $markerOccurrences = ([regex]::Matches($gitignoreContent, [regex]::Escape($script:GitignoreMarker))).Count
        if ($markerOccurrences -ne 1) { throw "expected the gitignore marker comment to appear exactly once, found $markerOccurrences occurrence(s)" }
    }

# ---------------------------------------------------------------------------
# Clean uninstall removes managed gitignore block + all installer state
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_RemoveGitignoreBlockArtifactsAndState_When_NothingDrifted' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $root
    } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Uninstall')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Removed local preferences entry from .gitignore.')) {
            throw "expected the gitignore block removal message. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Uninstall complete. Installer state removed.')) {
            throw "expected the clean uninstall-complete banner. Output: $($ctx.Result.Output)"
        }

        $gitignoreContent = Get-Content -LiteralPath (Join-Path $ctx.Root '.gitignore') -Raw
        if ($gitignoreContent -match [regex]::Escape($script:GitignoreEntry)) {
            throw "the gitignore entry must be fully removed after a clean uninstall"
        }
        if (Test-Path -LiteralPath (Get-InstructionsDir -TargetPath $ctx.Root)) {
            throw "the instructions directory (created by us and now empty) should be removed"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) {
            throw "installer state directory should be removed after a clean uninstall"
        }
    }

# ---------------------------------------------------------------------------
# -SkipGitignore
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_LeaveGitignoreUntouched_When_SkipGitignoreIsSpecified' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-SkipGitignore')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.gitignore')) {
            throw "'.gitignore' must not be created when -SkipGitignore is specified and none existed before"
        }
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.GitignoreManaged) { throw "expected manifest.GitignoreManaged to be false when -SkipGitignore was specified" }
        if (-not (Test-Path -LiteralPath (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md'))) {
            throw "template artifacts should still be installed even when -SkipGitignore is specified"
        }
    }

# ---------------------------------------------------------------------------
# Non-git preflight rejection: no mutation anywhere
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_FailPreflightWithNoMutation_When_TargetIsNotAGitRepository' `
    -Arrange { New-NonGitFixtureRoot } `
    -Act { param($root) [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root); Root = $root } } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit when the target is not a git repository" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('is not a git repository')) {
            throw "expected a not-a-git-repository preflight message. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.github')) { throw "'.github' must not be created when preflight fails" }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.gitignore')) { throw "'.gitignore' must not be created when preflight fails" }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw "no installer state should be created when preflight fails" }
        $remaining = @(Get-ChildItem -LiteralPath $ctx.Root -Force)
        if ($remaining.Count -ne 0) { throw "expected the non-git target to remain completely empty, found: $($remaining.Name -join ', ')" }
    }

# ---------------------------------------------------------------------------
# Parameter-set rejection
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_RejectParameterCombinationWithNoMutation_When_ForceAndUninstallAreBothSpecified' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Force', '-Uninstall')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit for a conflicting parameter-set combination" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Parameter set cannot be resolved')) {
            throw "expected a parameter-set resolution error. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) {
            throw "no installer state should be created when the parameter set itself is invalid"
        }
    }

# ---------------------------------------------------------------------------
# Legacy / no-manifest uninstall
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_ReportNothingTrackedWithNoMutation_When_NoManifestExists' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Uninstall')); Root = $root }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0, got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('No installer manifest found; nothing tracked to uninstall.')) {
            throw "expected the legacy no-manifest uninstall message. Output: $($ctx.Result.Output)"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) {
            throw "uninstalling with no prior manifest must not create any installer state"
        }
        if (Test-Path -LiteralPath (Join-Path $ctx.Root '.github')) {
            throw "uninstalling with no prior manifest must not create or touch '.github'"
        }
    }

# ---------------------------------------------------------------------------
# Safe behavior when the user modifies an installed file before uninstall
# ---------------------------------------------------------------------------

Test-Case -Name 'Uninstall_Should_PreserveUserEditedFileAndTrimManifest_When_FileWasModifiedBeforeUninstall' `
    -Arrange {
        $root = New-GitFixtureRoot
        Invoke-InstallProject -TargetPath $root | Out-Null
        $localPrefsPath = Join-Path (Get-InstructionsDir -TargetPath $root) 'local-preferences.instructions.md'
        $editedContent = 'USER EDIT BEFORE UNINSTALL - MUST SURVIVE'
        Set-Content -LiteralPath $localPrefsPath -Value $editedContent -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; LocalPrefsPath = $localPrefsPath; EditedContent = $editedContent }
    } `
    -Act {
        param($arranged)
        [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $arranged.Root -ExtraArgs @('-Uninstall')); Arranged = $arranged }
    } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -ne 0) { throw "expected exit 0 (a soft warning, not a hard failure), got $($ctx.Result.ExitCode). Output: $($ctx.Result.Output)" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('has been modified since install; leaving it in place')) {
            throw "expected a modified-since-install preservation warning. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('some items needed manual attention and were left in place')) {
            throw "expected the partial-uninstall summary banner. Output: $($ctx.Result.Output)"
        }

        if ((Get-Content -LiteralPath $ctx.Arranged.LocalPrefsPath -Raw) -ne $ctx.Arranged.EditedContent) {
            throw "the user-edited file must be left byte-for-byte unchanged; uninstall must never discard unrecognized edits"
        }

        # The cleanly-removed sibling artifact (project-config.instructions.md,
        # never touched by the user) must actually be gone...
        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $ctx.Arranged.Root) 'project-config.instructions.md'
        if (Test-Path -LiteralPath $projectConfigPath) { throw "expected the untouched sibling artifact to be removed by uninstall" }

        # ...while the trimmed manifest must still exist, tracking only the
        # still-conflicting artifact, so a future -Uninstall can retry it.
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Arranged.Root
        if (-not $manifest) { throw "expected a trimmed manifest to remain when a conflict prevents a full clean uninstall" }
        if (@($manifest.Artifacts).Count -ne 1) { throw "expected exactly 1 remaining artifact in the trimmed manifest, got $(@($manifest.Artifacts).Count)" }
        if (@($manifest.Artifacts)[0].Name -ne 'local-preferences.instructions.md') {
            throw "expected the remaining manifest artifact to be the still-conflicting local-preferences.instructions.md"
        }
    }

# ---------------------------------------------------------------------------
# Transactional rollback: a mid-run failure undoes everything written so far
# ---------------------------------------------------------------------------
#
# Failure seam: a directory (not a file) is pre-created at the target's
# .gitignore path. Set-GitignoreEntry's Add-Content call deterministically
# throws "Unable to write content because it is a directory" for such a
# path (verified interactively; no production code change involved — this
# is simply a hostile-but-valid pre-existing filesystem state, no different
# in kind from the foreign-symlink fixtures already used elsewhere in this
# repo's test suites). Both artifact files are written successfully before
# this failure, so this exercises rollback of populated 'WroteFile' and
# 'CreatedDirectory' transaction-log entries, not just an empty-log no-op.

Test-Case -Name 'Install_Should_RollBackWrittenArtifactsAndInstructionsDir_When_GitignoreWriteFailsMidTransaction' `
    -Arrange {
        $root = New-GitFixtureRoot
        New-Item -ItemType Directory -Path (Join-Path $root '.gitignore') | Out-Null
        $root
    } `
    -Act { param($root) [pscustomobject]@{ Result = (Invoke-InstallProject -TargetPath $root); Root = $root } } `
    -Assert {
        param($ctx)
        if ($ctx.Result.ExitCode -eq 0) { throw "expected a non-zero exit when the mid-transaction gitignore write fails" }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Install step failed:')) {
            throw "expected an install-step-failed message. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Rolling back changes made during this run...')) {
            throw "expected the rollback banner to fire. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Reverted WroteFile:')) {
            throw "expected at least one reverted WroteFile entry in the rollback log. Output: $($ctx.Result.Output)"
        }
        if ($ctx.Result.Output -notmatch [regex]::Escape('Reverted CreatedDirectory:')) {
            throw "expected the newly-created instructions directory entry to be reverted. Output: $($ctx.Result.Output)"
        }

        if (Test-Path -LiteralPath (Get-InstructionsDir -TargetPath $ctx.Root)) {
            throw "the instructions directory must not survive a rolled-back run"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) {
            throw "no installer state should persist after a fully rolled-back fresh install"
        }
        # Our precondition (the directory masquerading as .gitignore) is left
        # exactly as we made it — the installer never touches paths outside
        # its own recorded transaction log.
        if ((Get-Item -LiteralPath (Join-Path $ctx.Root '.gitignore') -Force).PSIsContainer -ne $true) {
            throw "the pre-existing .gitignore directory precondition should be untouched by rollback"
        }
    }

# ---------------------------------------------------------------------------
# BackupPath carry-forward across a template refresh (isolated script-copy
# fixture: only the disposable COPY's templates are edited to simulate a
# source template revision; this repo's real templates are never touched).
# ---------------------------------------------------------------------------

Test-Case -Name 'Install_Should_CarryForwardEarliestBackupAndUninstallRestorePreExistingContent_When_TemplateIsRevisedThenRefreshedThenUninstalled' `
    -Arrange {
        $scriptCopy = New-InstallProjectScriptCopy
        $root = New-GitFixtureRoot
        $instructionsDir = Get-InstructionsDir -TargetPath $root
        New-Item -ItemType Directory -Path $instructionsDir -Force | Out-Null
        $projectConfigPath = Join-Path $instructionsDir 'project-config.instructions.md'
        $preExistingContent = 'PRE-EXISTING USER CONTENT - MUST SURVIVE TEMPLATE REVISIONS AND REFRESHES'
        Set-Content -LiteralPath $projectConfigPath -Value $preExistingContent -Encoding utf8 -NoNewline

        $forceResult = Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Force') -ScriptPath $scriptCopy.ScriptPath
        if ($forceResult.ExitCode -ne 0) { throw "arrange: -Force install failed: $($forceResult.Output)" }
        $manifestAfterForce = Import-ProjectTestManifest -TargetPath $root
        $artifactAfterForce = @($manifestAfterForce.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        if (-not $artifactAfterForce.BackupPath) { throw "arrange: expected the pre-existing content to be backed up by -Force" }

        # Simulate a source template revision landing in the repo, WITHOUT
        # touching this repo's real templates directory.
        Set-InstallProjectScriptCopyTemplateContent -ScriptCopyTemplatesDir $scriptCopy.TemplatesDir `
            -FileName 'project-config.instructions.md' -Content 'REVISED TEMPLATE V2 CONTENT - SIMULATED SOURCE CHANGE'

        [pscustomobject]@{
            Root = $root; ScriptCopy = $scriptCopy; ProjectConfigPath = $projectConfigPath
            PreExistingContent = $preExistingContent; BackupPathAfterForce = $artifactAfterForce.BackupPath
            CleanupPaths = @($root, $scriptCopy.Root)
        }
    } `
    -Act {
        param($arranged)
        $refreshResult = Invoke-InstallProject -TargetPath $arranged.Root -ScriptPath $arranged.ScriptCopy.ScriptPath
        $manifestAfterRefresh = Import-ProjectTestManifest -TargetPath $arranged.Root
        $artifactAfterRefresh = @($manifestAfterRefresh.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        # Read the backup's content NOW, before -Uninstall runs: a clean,
        # conflict-free uninstall removes the whole installer state
        # directory (including backups\) once it has finished restoring, so
        # the backup file itself will no longer exist for inspection after
        # the next step.
        $backupContentAfterRefresh = if ($artifactAfterRefresh.BackupPath -and (Test-Path -LiteralPath $artifactAfterRefresh.BackupPath)) {
            Get-Content -LiteralPath $artifactAfterRefresh.BackupPath -Raw
        }
        else { $null }

        $uninstallResult = Invoke-InstallProject -TargetPath $arranged.Root -ExtraArgs @('-Uninstall') -ScriptPath $arranged.ScriptCopy.ScriptPath
        [pscustomobject]@{
            RefreshResult = $refreshResult; BackupPathAfterRefresh = $artifactAfterRefresh.BackupPath
            BackupContentAfterRefresh = $backupContentAfterRefresh
            UninstallResult = $uninstallResult; Arranged = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.RefreshResult.ExitCode -ne 0) { throw "expected exit 0 on refresh, got $($ctx.RefreshResult.ExitCode). Output: $($ctx.RefreshResult.Output)" }
        if ($ctx.RefreshResult.Output -notmatch [regex]::Escape('refreshed to current template')) {
            throw "expected a refresh confirmation. Output: $($ctx.RefreshResult.Output)"
        }

        if ($ctx.BackupPathAfterRefresh -ne $ctx.Arranged.BackupPathAfterForce) {
            throw "expected the manifest's BackupPath to still point at the pre-Force backup after a template refresh, but it changed from '$($ctx.Arranged.BackupPathAfterForce)' to '$($ctx.BackupPathAfterRefresh)'"
        }
        if ($ctx.BackupContentAfterRefresh -ne $ctx.Arranged.PreExistingContent) {
            throw "the earliest backup must still contain the original pre-existing user content, not a later refresh's own template output"
        }

        if ($ctx.UninstallResult.ExitCode -ne 0) { throw "expected exit 0 on uninstall, got $($ctx.UninstallResult.ExitCode). Output: $($ctx.UninstallResult.Output)" }
        if ($ctx.UninstallResult.Output -notmatch [regex]::Escape('Restored previous content to')) {
            throw "expected an uninstall restoration message. Output: $($ctx.UninstallResult.Output)"
        }

        $finalContent = Get-Content -LiteralPath $ctx.Arranged.ProjectConfigPath -Raw
        if ($finalContent -ne $ctx.Arranged.PreExistingContent) {
            throw "expected the original pre-existing user content to be restored by -Uninstall, not the v1 or v2 template content. Actual: $finalContent"
        }
    }

Test-Case -Name 'Uninstall_Should_RemoveInstallerCreatedArtifactWithoutRestoringStaleTemplate_When_TemplateIsRevisedThenRefreshedThenUninstalled' `
    -Arrange {
        $scriptCopy = New-InstallProjectScriptCopy
        $root = New-GitFixtureRoot
        $installResult = Invoke-InstallProject -TargetPath $root -ScriptPath $scriptCopy.ScriptPath
        if ($installResult.ExitCode -ne 0) { throw "arrange: fresh install failed: $($installResult.Output)" }

        $manifestAfterInstall = Import-ProjectTestManifest -TargetPath $root
        $artifactAfterInstall = @($manifestAfterInstall.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        if ($artifactAfterInstall.BackupPath) { throw "arrange: expected no BackupPath for a fresh installer-created artifact" }

        # Simulate a source template revision landing in the repo, WITHOUT
        # touching this repo's real templates directory.
        Set-InstallProjectScriptCopyTemplateContent -ScriptCopyTemplatesDir $scriptCopy.TemplatesDir `
            -FileName 'project-config.instructions.md' -Content 'REVISED TEMPLATE V2 CONTENT FOR CLEAN INSTALLER ARTIFACT'

        $projectConfigPath = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        [pscustomobject]@{
            Root = $root; ScriptCopy = $scriptCopy; ProjectConfigPath = $projectConfigPath
            CleanupPaths = @($root, $scriptCopy.Root)
        }
    } `
    -Act {
        param($arranged)
        $refreshResult = Invoke-InstallProject -TargetPath $arranged.Root -ScriptPath $arranged.ScriptCopy.ScriptPath
        $manifestAfterRefresh = Import-ProjectTestManifest -TargetPath $arranged.Root
        $uninstallResult = Invoke-InstallProject -TargetPath $arranged.Root -ExtraArgs @('-Uninstall') -ScriptPath $arranged.ScriptCopy.ScriptPath
        [pscustomobject]@{
            RefreshResult = $refreshResult; ManifestAfterRefresh = $manifestAfterRefresh
            UninstallResult = $uninstallResult; Arranged = $arranged
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.RefreshResult.ExitCode -ne 0) { throw "expected exit 0 on refresh, got $($ctx.RefreshResult.ExitCode). Output: $($ctx.RefreshResult.Output)" }
        if ($ctx.RefreshResult.Output -notmatch [regex]::Escape('refreshed to current template')) {
            throw "expected a refresh confirmation. Output: $($ctx.RefreshResult.Output)"
        }

        $artifactAfterRefresh = @($ctx.ManifestAfterRefresh.Artifacts) | Where-Object { $_.Name -eq 'project-config.instructions.md' }
        if ($artifactAfterRefresh.BackupPath) {
            throw "expected BackupPath to remain unset for an artifact the installer itself created, even after a refresh; got '$($artifactAfterRefresh.BackupPath)'"
        }

        if ($ctx.UninstallResult.ExitCode -ne 0) { throw "expected exit 0 on uninstall, got $($ctx.UninstallResult.ExitCode). Output: $($ctx.UninstallResult.Output)" }
        if ($ctx.UninstallResult.Output -notmatch [regex]::Escape('Removed:')) {
            throw "expected a removal message. Output: $($ctx.UninstallResult.Output)"
        }
        if ($ctx.UninstallResult.Output -match [regex]::Escape('Restored previous content to')) {
            throw "an installer-created artifact must never be 'restored' to a stale template snapshot. Output: $($ctx.UninstallResult.Output)"
        }

        if (Test-Path -LiteralPath $ctx.Arranged.ProjectConfigPath) {
            throw "expected the installer-created artifact to be removed entirely by -Uninstall, not left behind with stale template content"
        }
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Arranged.Root)) {
            throw "no installer state should persist after a clean uninstall"
        }
    }

# ---------------------------------------------------------------------------
# Hermeticity guard: this suite must never mutate the real repository's own
# working tree/templates, or the real Copilot home.
# ---------------------------------------------------------------------------

Test-Case -Name 'Suite_Should_NeverMutate_RealRepoOrCopilotHome_AcrossAnyTest' `
    -Arrange { $null } `
    -Act { param($unused) [pscustomobject]@{ ExitCode = 0; Output = '' } } `
    -Assert {
        param($r)
        $templatesHashAfter = (Get-ChildItem -LiteralPath $script:TemplatesDir -Recurse -File |
                Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ','
        if ($templatesHashAfter -ne $script:RepoTemplatesHashBefore) {
            throw "the repository's own templates directory changed during this test run"
        }

        $repoStateDirExistsNow = Test-Path -LiteralPath (Join-Path $script:InstallProjectRepoRoot $script:StateDirName)
        if ($repoStateDirExistsNow -ne $script:RepoRootStateDirExistedBefore) {
            throw "a fixture appears to have leaked installer state into this repository's own root"
        }

        $copilotHomeStateDirExistsNow = Test-Path -LiteralPath (Join-Path $script:RealCopilotHome $script:StateDirName)
        if ($copilotHomeStateDirExistsNow -ne $script:RealCopilotProjectStateDirExistedBefore) {
            throw "a fixture appears to have leaked installer state into the real Copilot home ($script:RealCopilotHome)"
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
