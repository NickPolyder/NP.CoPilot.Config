#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

Test-Case -Name 'Suite_InputGuard_Should_ExcludeRootDocsAndReportExactTemplateChanges' `
    -Arrange { New-ProjectFrozenTestSource } `
    -Act {
        param($snapshot)
        $before = @(Get-ProjectTestSourceManifest -Root $snapshot.Root)
        Set-Content -LiteralPath (Join-Path $snapshot.Root 'README.md') -Value 'ROOT README EDIT - NOT A TEMPLATE'
        New-Item -ItemType Directory -Path (Join-Path $snapshot.Root '.github') | Out-Null
        Set-Content -LiteralPath (Join-Path $snapshot.Root '.github\copilot-instructions.md') -Value 'ROOT GUIDANCE EDIT - NOT A TEMPLATE'
        $rootDocChanges = @(Compare-ProjectTestSourceManifest -Expected $before -Actual @(Get-ProjectTestSourceManifest -Root $snapshot.Root))
        if ($rootDocChanges.Count) { throw "Root-only documentation incorrectly entered the source guard: $($rootDocChanges.Path -join ', ')" }
        Add-Content -LiteralPath (Join-Path $snapshot.Root 'templates\repo-bootstrap\README.md') -Value 'ACTUAL TEMPLATE EDIT'
        $changes = @(Compare-ProjectTestSourceManifest -Expected $before -Actual @(Get-ProjectTestSourceManifest -Root $snapshot.Root))
        if ($changes.Count -ne 1 -or $changes[0].Path -cne 'templates\repo-bootstrap\README.md') {
            throw "Source guard did not identify the exact changed template: $($changes.Path -join ', ')"
        }
        $snapshot
    } `
    -Assert { param($snapshot) }

Test-Case -Name 'Suite_FrozenSource_Should_KeepInstallerAndAssertionsTogetherDespiteOriginEdits' `
    -Arrange {
        $origin = New-ProjectFrozenTestSource
        $frozen = New-ProjectFrozenTestSource -SourceRoot $origin.Root
        [pscustomobject]@{ Root = $origin.Root; Frozen = $frozen; CleanupPaths = @($origin.Root, $frozen.Root) }
    } `
    -Act {
        param($ctx)
        $installerPath = Join-Path $ctx.Root 'install-project.ps1'
        $installer = [IO.File]::ReadAllText($installerPath)
        $changed = $installer.Replace('](../copilot-instructions.md)', '](../copilot-instructions.md#delivery-capabilities)')
        if ($changed -ceq $installer) { throw 'Fixture did not change the real capability-reference contract.' }
        Set-Content -LiteralPath $installerPath -Value $changed -Encoding utf8 -NoNewline
        Add-Content -LiteralPath (Join-Path $ctx.Root 'templates\repo-bootstrap\README.md') -Value 'LATER SOURCE DOCUMENTATION EDIT'
        $result = Invoke-ProjectFixtureProcess -Program pwsh -Arguments @('-NoProfile', '-File', $ctx.Frozen.RunnerPath,
            '-FrozenSources', '-NamePattern', 'C04_RootCapabilityOwner_Generic_*') -WorkingDirectory $ctx.Frozen.Root
        Assert-ProjectRunSucceeded -Result $result
        if ($result.Output -notmatch 'All 1 regression tests passed') { throw "The frozen source test did not execute: $($result.Output)" }
        Assert-ProjectFrozenTestSource -Root $ctx.Frozen.Root | Out-Null
        $changes = @(Compare-ProjectTestSourceManifest -Expected $ctx.Frozen.Manifest.Files -Actual @(Get-ProjectTestSourceManifest -Root $ctx.Root))
        if ($changes.Count -ne 2 -or 'install-project.ps1' -cnotin $changes.Path -or
            'templates\repo-bootstrap\README.md' -cnotin $changes.Path) {
            throw 'Live-source drift was not reported independently of the passing frozen execution.'
        }
        $ctx
    } `
    -Assert { param($ctx) }

Test-Case -Name 'C04_ReferenceDiagnostics_Should_DistinguishWrongFragmentsFromDuplicateTables' `
    -Arrange { New-NonGitFixtureRoot } `
    -Act {
        param($root)
        $path = Join-Path $root 'reference.md'
        $content = "## Agent Delivery Capabilities`n`n<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`n`nThe [root project contract](../copilot-instructions.md#delivery-capabilities) owns capabilities.`n"
        Set-Content -LiteralPath $path -Value $content -Encoding utf8 -NoNewline
        $failure = $null
        try { Assert-ProjectRootCapabilityReference -Path $path }
        catch { $failure = $_.Exception.Message }
        if (-not $failure -or $failure -notmatch 'reference mismatch' -or $failure -match 'duplicate capability table') {
            throw 'A reference mismatch was misreported as a duplicate capability declaration.'
        }
        $content = $content.Replace('#delivery-capabilities', '') + "`n| Capability | Enabled | Repository-specific rule |`n"
        Set-Content -LiteralPath $path -Value $content -Encoding utf8 -NoNewline
        $failure = $null
        try { Assert-ProjectRootCapabilityReference -Path $path }
        catch { $failure = $_.Exception.Message }
        if (-not $failure -or $failure -notmatch 'duplicate capability table' -or $failure -match 'reference mismatch') {
            throw 'A real duplicate capability table was not reported accurately.'
        }
        $root
    } `
    -Assert { param($root) }

Test-Case -Name 'Isolation_Should_ControlChildHomesTempAndGitConfigurationAndClearInheritedRouting' `
    -Arrange { New-GitFixtureRoot } `
    -Act {
        param($root)
        $poison = Join-Path $root 'inherited-index-sentinel'
        Set-Content -LiteralPath $poison -Value 'DO NOT USE OR WRITE THIS INDEX' -NoNewline
        $before = Get-ProjectFixtureSnapshot -Root $root
        $controls = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
            'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CEILING_DIRECTORIES', 'GIT_CONFIG_COUNT',
            'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG', 'GIT_EXEC_PATH')
        $saved = @{}
        try {
            foreach ($name in $controls) {
                $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                [Environment]::SetEnvironmentVariable($name, $poison, 'Process')
            }
            $probe = Invoke-ProjectFixtureProcess -Program pwsh -Arguments @('-NoProfile', '-Command',
                '[pscustomobject]@{ PowerShellHome = $HOME; HOME = $env:HOME; USERPROFILE = $env:USERPROFILE; COPILOT_HOME = $env:COPILOT_HOME; TEMP = $env:TEMP; TMP = $env:TMP; TempPath = [IO.Path]::GetTempPath(); GlobalConfig = $env:GIT_CONFIG_GLOBAL; NoSystem = $env:GIT_CONFIG_NOSYSTEM; Controls = @(Get-ChildItem Env: | Where-Object Name -Match "^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|CEILING_DIRECTORIES|CONFIG_COUNT|CONFIG_KEY_0|CONFIG_VALUE_0|CONFIG_PARAMETERS|CONFIG|EXEC_PATH)$" | Select-Object -ExpandProperty Name) } | ConvertTo-Json -Depth 4')
            $git = Invoke-ProjectFixtureGit -Root $root -Arguments @('config', '--global', '--list', '--show-origin')
        }
        finally {
            foreach ($name in $controls) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
        [pscustomobject]@{ Root = $root; Before = $before; Probe = $probe; Git = $git }
    } `
    -Assert {
        param($ctx)
        Assert-ProjectRunSucceeded -Result $ctx.Probe
        Assert-ProjectRunSucceeded -Result $ctx.Git
        $environment = $ctx.Probe.Stdout | ConvertFrom-Json
        foreach ($name in @('HOME', 'USERPROFILE', 'COPILOT_HOME', 'TEMP', 'TMP')) {
            if ($environment.$name -cne $script:ProjectTestEnvironment[$name]) { throw "Child $name was not fixture-owned." }
        }
        if ($environment.PowerShellHome -cne $script:ProjectTestEnvironment.HOME) { throw 'Child PowerShell HOME was not isolated.' }
        if ($environment.TempPath.TrimEnd('\') -cne $script:ProjectTestEnvironment.TEMP) { throw 'Child runtime temp path was not isolated.' }
        if ($environment.Controls.Count) { throw "Inherited Git controls survived: $($environment.Controls -join ', ')" }
        if ($environment.NoSystem -ne '1' -or $environment.GlobalConfig -cne $script:ProjectTestEnvironment.GIT_CONFIG_GLOBAL) {
            throw 'Child Git configuration was not isolated.'
        }
        if ($ctx.Git.Stdout.Trim()) { throw 'An empty fixture global Git configuration unexpectedly supplied settings.' }
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'An inherited Git routing sentinel was changed.' }
    }

Test-Case -Name 'H01_P01_CopiedManifest_Should_RejectInstallForceUninstallAndPreviewWithoutMutatingEitherRepository' `
    -Arrange {
        $a = New-ProjectOriginalFixture
        $b = New-GitFixtureRoot
        foreach ($name in @('.github', $script:StateDirName, '.gitignore')) {
            Copy-Item -LiteralPath (Join-Path $a.Root $name) -Destination (Join-Path $b $name) -Recurse
        }
        [pscustomobject]@{ A = $a.Root; B = $b; BeforeA = (Get-ProjectFixtureSnapshot -Root $a.Root)
            BeforeB = (Get-ProjectFixtureSnapshot -Root $b); CleanupPaths = @($a.Root, $b) }
    } `
    -Act {
        param($ctx)
        foreach ($arguments in @(@(), @('-Force'), @('-Uninstall'), @('-WhatIf'), @('-Uninstall', '-WhatIf'))) {
            Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.B -ExtraArgs $arguments) -Pattern 'target binding mismatch'
            if ((Get-ProjectFixtureSnapshot -Root $ctx.A) -cne $ctx.BeforeA -or
                (Get-ProjectFixtureSnapshot -Root $ctx.B) -cne $ctx.BeforeB) {
                throw 'Copied state mutated source or destination repository.'
            }
        }
        $ctx
    } `
    -Assert { param($ctx) }

Test-Case -Name 'H01_NormalizedRelativeInput_Should_RemainBoundAcrossWorkingDirectories' `
    -Arrange {
        $root = New-GitFixtureRoot
        $other = New-GitFixtureRoot
        [pscustomobject]@{ Root = $root; Other = $other; BeforeOther = (Get-ProjectFixtureSnapshot -Root $other)
            CleanupPaths = @($root, $other) }
    } `
    -Act {
        param($ctx)
        $relative = '.\' + (Split-Path $ctx.Root -Leaf) + '\.'
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $relative)
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.TargetPath -cne $ctx.Root) { throw 'Manifest target was not normalized and absolute.' }
        foreach ($artifact in $manifest.Artifacts) {
            if ($artifact.TargetPath -cne (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) $artifact.Name)) {
                throw 'Artifact destination was not derived from the normalized target.'
            }
        }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath ($ctx.Root + '\.') -WorkingDirectory $ctx.Other -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw 'Same-target uninstall did not finish.' }
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Other) -cne $ctx.BeforeOther) { throw 'Working-directory change redirected an operation.' }
    }

$invalidStates = @('InvalidJson', 'NullRoot', 'ArrayRoot', 'UnsupportedVersion', 'StringVersion', 'RelativeRoot',
    'MissingField', 'StringBoolean', 'ObjectArtifacts', 'DuplicateArtifact', 'UnknownArtifact', 'InvalidHash',
    'InvalidStatus', 'RelativeArtifactPath', 'WrongArtifactPath', 'RelativeBackupPath', 'OutsideBackupLayout',
    'MissingBackupIdentity', 'InvalidBackupKind', 'InvalidIgnoreId', 'InvalidIgnoreHash', 'DisabledOwnedPolicy',
    'NullRetainedBackups', 'DuplicateJsonProperty')
foreach ($invalidState in $invalidStates) {
    Test-Case -Name "H01_H02_P07_InvalidState_${invalidState}_Should_FailClosedEvenWithForce" `
        -Arrange {
            $ctx = New-ProjectOriginalFixture
            $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
            $json = $null
            switch ($invalidState) {
                'InvalidJson' { $json = '{"SchemaVersion":' }
                'NullRoot' { $json = 'null' }
                'ArrayRoot' { $json = '[]' }
                'UnsupportedVersion' { $manifest.SchemaVersion = 99 }
                'StringVersion' { $manifest.SchemaVersion = '2' }
                'RelativeRoot' { $manifest.TargetPath = '.' }
                'MissingField' { $manifest.PSObject.Properties.Remove('TargetPath') }
                'StringBoolean' { $manifest.GitignoreManaged = 'true' }
                'ObjectArtifacts' { $manifest.Artifacts = $manifest.Artifacts[0] }
                'DuplicateArtifact' { $manifest.Artifacts = @($manifest.Artifacts[0], $manifest.Artifacts[0]) }
                'UnknownArtifact' { $manifest.Artifacts[0].Name = 'unowned.instructions.md' }
                'InvalidHash' { $manifest.Artifacts[0].InstalledHash = 'not-a-sha256' }
                'InvalidStatus' { $manifest.Artifacts[0].Status = 'Unrecognized' }
                'RelativeArtifactPath' { $manifest.Artifacts[0].TargetPath = '.github\instructions\project-config.instructions.md' }
                'WrongArtifactPath' { $manifest.Artifacts[0].TargetPath = Join-Path $ctx.Root 'foreign.txt' }
                'RelativeBackupPath' { $manifest.Artifacts[0].BackupPath = '.np-copilot-project-installer\backups\original.md' }
                'OutsideBackupLayout' { $manifest.Artifacts[0].BackupPath = Join-Path $ctx.Root '.github\instructions\project-config.instructions.md' }
                'MissingBackupIdentity' { $manifest.Artifacts[0].PSObject.Properties.Remove('BackupIdentity') }
                'InvalidBackupKind' { $manifest.Artifacts[0].BackupIdentity.Kind = 'Directory' }
                'InvalidIgnoreId' { $manifest.GitignoreBlocks[0].Id = '..\manifest.json' }
                'InvalidIgnoreHash' { $manifest.GitignoreBlocks[0].PrefixHash = 'invalid' }
                'DisabledOwnedPolicy' { $manifest.GitignorePolicyEnabled = $false }
                'NullRetainedBackups' { $manifest.RetainedBackups = $null }
                'DuplicateJsonProperty' { $json = ($manifest | ConvertTo-Json -Depth 20).Replace('"SchemaVersion": 2,', '"SchemaVersion": 2, "SchemaVersion": 2,') }
            }
            if ($null -ne $json) { Set-Content -LiteralPath $ctx.ManifestPath -Value $json -Encoding utf8 -NoNewline }
            else { Save-ProjectTestManifest -Root $ctx.Root -Manifest $manifest }
            $ctx | Add-Member -NotePropertyName Before -NotePropertyValue (Get-ProjectFixtureSnapshot -Root $ctx.Root)
            $ctx
        } `
        -Act {
            param($ctx)
            foreach ($arguments in @(@('-Force'), @('-Uninstall'))) {
                Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'Invalid or unreadable installer state'
                if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Invalid state was mutated or adopted.' }
            }
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.BackupPath) -cne $ctx.OriginalHash) { throw 'Invalid state lost its recovery bytes.' }
        }
}

Test-Case -Name 'H02_UnreadablePresentManifest_Should_FailClosedAndRemainRecoverable' `
    -Arrange { New-ProjectOriginalFixture } `
    -Act {
        param($ctx)
        $before = Get-ProjectFixtureSnapshot -Root $ctx.Root
        $lock = [IO.File]::Open($ctx.ManifestPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            foreach ($arguments in @(@('-Force'), @('-Uninstall'))) {
                Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'Invalid or unreadable installer state'
            }
        }
        finally { $lock.Dispose() }
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $before) { throw 'Unreadable manifest or recovery artifacts changed.' }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Unlock/retry did not restore the original.' }
    }

foreach ($stateCollision in @('MissingManifest', 'ManifestDirectory')) {
    Test-Case -Name "H02_${stateCollision}_Should_NotTreatPresentStateAsAbsent" `
        -Arrange {
            $ctx = New-ProjectOriginalFixture
            Move-Item -LiteralPath $ctx.ManifestPath -Destination ($ctx.ManifestPath + '.saved')
            if ($stateCollision -eq 'ManifestDirectory') {
                New-Item -ItemType Directory -Path $ctx.ManifestPath | Out-Null
                Set-Content -LiteralPath (Join-Path $ctx.ManifestPath 'sentinel') -Value 'PRESERVE'
            }
            $ctx | Add-Member -NotePropertyName Before -NotePropertyValue (Get-ProjectFixtureSnapshot -Root $ctx.Root)
            $ctx
        } `
        -Act {
            param($ctx)
            foreach ($arguments in @(@('-Force'), @('-Uninstall'))) {
                Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'without manifest.json|Directory collision'
            }
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Present unusable state was changed.' }
        }
}

Test-Case -Name 'H01_H02_LegacyManifest_Should_MigrateBindingAndRestoreWithoutAdoptingForeignIgnoreBlock' `
    -Arrange {
        $ctx = New-ProjectOriginalFixture
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        $manifest.SchemaVersion = 1
        foreach ($name in @('GitignorePolicyEnabled', 'GitignoreEffective', 'GitignoreBlocks', 'RetainedBackups')) {
            $manifest.PSObject.Properties.Remove($name)
        }
        foreach ($artifact in $manifest.Artifacts) { $artifact.PSObject.Properties.Remove('BackupIdentity') }
        Save-ProjectTestManifest -Root $ctx.Root -Manifest $manifest
        $legacyIgnore = "$script:GitignoreMarker`r`n$script:GitignoreEntry`r`n"
        Set-Content -LiteralPath (Join-Path $ctx.Root '.gitignore') -Value $legacyIgnore -Encoding utf8 -NoNewline
        $ctx | Add-Member -NotePropertyName LegacyIgnore -NotePropertyValue $legacyIgnore
        $ctx
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.SchemaVersion -ne 2 -or $manifest.Artifacts[0].BackupPath -cne $ctx.BackupPath) {
            throw 'Legacy migration lost its original restore point.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths @($ctx.BackupPath)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Legacy original was not restored.' }
        if ([IO.File]::ReadAllText((Join-Path $ctx.Root '.gitignore')) -cne $ctx.LegacyIgnore) {
            throw 'Legacy boolean ownership was incorrectly used to remove a foreign ignore block.'
        }
    }

foreach ($missingTarget in @($false, $true)) {
    Test-Case -Name "H04_P05_LockedBackup_MissingTarget_${missingTarget}_Should_PreserveOriginalAndRestoreOnRetry" `
        -Arrange {
            $ctx = New-ProjectOriginalFixture
            if ($missingTarget) { Remove-Item -LiteralPath $ctx.Path }
            $ctx
        } `
        -Act {
            param($ctx)
            $before = Get-ProjectFixtureSnapshot -Root $ctx.Root
            $lock = [IO.File]::Open($ctx.BackupPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            try { Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')) }
            finally { $lock.Dispose() }
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $before) { throw 'A locked backup caused mutation before it could be restored.' }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Retry did not restore the original SHA-256.' }
            if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw 'Completed recovery state was not pruned.' }
        }
}

Test-Case -Name 'H04_LockedRestoreDestination_Should_KeepPendingCheckpointAndRestoreOnRetry' `
    -Arrange { New-ProjectOriginalFixture } `
    -Act {
        param($ctx)
        $installedHash = Get-Sha256TestFileHash -Path $ctx.Path
        $lock = [IO.File]::Open($ctx.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')) }
        finally { $lock.Dispose() }
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $installedHash -or
            (Get-Sha256TestFileHash -Path $ctx.BackupPath) -cne $ctx.OriginalHash) { throw 'Failed atomic restoration lost destination or original bytes.' }
        $pending = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($pending.Artifacts[0].Status -cne 'RestorePending') { throw 'Failed replacement lost its pending recovery checkpoint.' }
        if (@(Get-ChildItem -LiteralPath (Get-InstructionsDir -TargetPath $ctx.Root) -Filter '.np-restore-*.tmp').Count) {
            throw 'Failed restoration left staging files behind.'
        }
        Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force')) -Pattern 'pending recovery'
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Pending recovery retry did not restore the original.' }
    }

foreach ($recoveryPhase in @('RestorePending', 'Restored')) {
    Test-Case -Name "H04_Interrupted_${recoveryPhase}_Should_RecognizeVerifiedRestoration" `
        -Arrange {
            $ctx = New-ProjectOriginalFixture
            Copy-Item -LiteralPath $ctx.BackupPath -Destination $ctx.Path -Force
            $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
            $manifest.Artifacts[0].Status = $recoveryPhase
            Save-ProjectTestManifest -Root $ctx.Root -Manifest $manifest
            if ($recoveryPhase -eq 'Restored') { Remove-Item -LiteralPath $ctx.BackupPath }
            $ctx
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Checkpoint recovery changed the restored original.' }
            if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw 'Completed checkpoint did not finish cleanup.' }
        }
}

foreach ($forceAdoption in @($false, $true)) {
    Test-Case -Name "M07_P02_IdenticalForeignFiles_Force_${forceAdoption}_Should_SurviveInstallRepeatAndUninstall" `
        -Arrange {
            $root = New-GitFixtureRoot
            New-Item -ItemType Directory -Path (Get-InstructionsDir -TargetPath $root) -Force | Out-Null
            foreach ($name in @('project-config.instructions.md', 'local-preferences.instructions.md')) {
                Copy-Item -LiteralPath (Join-Path $script:TemplatesDir $name) -Destination (Join-Path (Get-InstructionsDir -TargetPath $root) $name)
            }
            $root
        } `
        -Act {
            param($root)
            $arguments = @()
            if ($forceAdoption) { $arguments = @('-Force') }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root -ExtraArgs $arguments)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
            $manifest = Import-ProjectTestManifest -TargetPath $root
            foreach ($artifact in $manifest.Artifacts) {
                if ($forceAdoption) {
                    if ($artifact.Status -cne 'Managed' -or -not $artifact.BackupPath) { throw 'Explicit identical adoption did not preserve a restore point.' }
                    if ((Get-Sha256TestFileHash -Path $artifact.BackupPath) -cne (Get-Sha256TestFileHash -Path $artifact.TargetPath)) {
                        throw 'Identical adoption backup does not match the foreign file.'
                    }
                }
                elseif ($artifact.Status -cne 'Conflict' -or $artifact.BackupPath) { throw 'First-run identical foreign file was silently adopted.' }
            }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Uninstall'))
            $root
        } `
        -Assert {
            param($root)
            foreach ($name in @('project-config.instructions.md', 'local-preferences.instructions.md')) {
                if ((Get-Sha256TestFileHash -Path (Join-Path (Get-InstructionsDir -TargetPath $root) $name)) -cne
                    (Get-Sha256TestFileHash -Path (Join-Path $script:TemplatesDir $name))) {
                    throw 'An identical foreign file was deleted or changed.'
                }
            }
            Assert-ProjectPrivacy -Root $root
        }
}

Test-Case -Name 'H06_P03_P04_ForceAndPartialUninstall_Should_KeepPersonalFilesStateAndEveryBackupActuallyIgnored' `
    -Arrange { New-ProjectOriginalFixture -Name 'local-preferences.instructions.md' -Original 'PERSONAL ORIGINAL - PRIVATE FIXTURE DATA' } `
    -Act {
        param($ctx)
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths @($ctx.BackupPath)
        Set-Content -LiteralPath $ctx.Path -Value 'SECOND PERSONAL VERSION' -Encoding utf8 -NoNewline
        $secondHash = Get-Sha256TestFileHash -Path $ctx.Path
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.RetainedBackups.Count -ne 1 -or (Get-Sha256TestFileHash -Path $manifest.RetainedBackups[0]) -cne $secondHash) {
            throw 'A later Force backup was not retained independently of the original restore point.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths (@($ctx.BackupPath) + $manifest.RetainedBackups)
        Set-Content -LiteralPath $ctx.Path -Value 'EDITED PERSONAL FILE LEFT DURING PARTIAL UNINSTALL' -Encoding utf8 -NoNewline
        $editedHash = Get-Sha256TestFileHash -Path $ctx.Path
        $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')
        Assert-ProjectRunSucceeded -Result $result
        if ($result.Output -notmatch 'some items needed manual attention') { throw 'Partial uninstall was reported as fully complete.' }
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $editedHash) { throw 'Partial uninstall changed personal bytes.' }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths (@($ctx.BackupPath) + $manifest.RetainedBackups)
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.BackupPath) -cne $ctx.OriginalHash) { throw 'The earliest private original became unrecoverable.' }
        if (-not (Import-ProjectTestManifest -TargetPath $ctx.Root).GitignoreManaged) { throw 'Partial uninstall relinquished necessary owned exclusions.' }
    }

Test-Case -Name 'H04_H06_AdditionalOriginals_Should_RemainRecoverableAfterPrimaryRestoration' `
    -Arrange { New-ProjectOriginalFixture -Name 'local-preferences.instructions.md' } `
    -Act {
        param($ctx)
        Set-Content -LiteralPath $ctx.Path -Value 'LATER ORIGINAL - MUST ALSO SURVIVE' -Encoding utf8 -NoNewline
        $laterHash = Get-Sha256TestFileHash -Path $ctx.Path
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
        $later = (Import-ProjectTestManifest -TargetPath $ctx.Root).RetainedBackups[0]
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        if ((Get-Sha256TestFileHash -Path $later) -cne $laterHash) { throw 'Cleanup discarded an unconsumed later original.' }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths @($later)
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Primary restoration did not restore the earliest original.' }
        if (-not (Test-Path -LiteralPath $ctx.ManifestPath)) { throw 'Additional recovery material lost its state record.' }
    }

Test-Case -Name 'H01_RetainedRecoveryPaths_Should_BeNormalizedBeforePersistenceAndUse' `
    -Arrange { New-ProjectOriginalFixture } `
    -Act {
        param($ctx)
        Set-Content -LiteralPath $ctx.Path -Value 'SECOND DISTINCT ORIGINAL'
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        $canonical = $manifest.RetainedBackups[0]
        $manifest.RetainedBackups[0] = Join-Path (Split-Path $canonical -Parent) ('.\' + (Split-Path $canonical -Leaf))
        Save-ProjectTestManifest -Root $ctx.Root -Manifest $manifest
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        if ((Import-ProjectTestManifest -TargetPath $ctx.Root).RetainedBackups[0] -cne $canonical) {
            throw 'Retained recovery paths were validated but later used/persisted without normalization.'
        }
        $ctx
    } `
    -Assert { param($ctx) }

Test-Case -Name 'H04_MissingConflictedTarget_Should_RetainItsOriginalAndRecoveryRecord' `
    -Arrange { New-ProjectOriginalFixture } `
    -Act {
        param($ctx)
        Set-Content -LiteralPath $ctx.Path -Value 'CONFLICTING USER EDIT'
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        Remove-Item -LiteralPath $ctx.Path
        $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')
        Assert-ProjectRunSucceeded -Result $result
        if ($result.Output -notmatch 'is missing but has a conflicted recovery record') { throw 'Missing-target recovery state was not reported accurately.' }
        $ctx
    } `
    -Assert {
        param($ctx)
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.Artifacts.Count -ne 1 -or $manifest.Artifacts[0].BackupPath -cne $ctx.BackupPath -or
            (Get-Sha256TestFileHash -Path $ctx.BackupPath) -cne $ctx.OriginalHash) {
            throw 'A missing conflicted target caused its only original/record to be discarded.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths @($ctx.BackupPath)
    }

Test-Case -Name 'H04_H06_UnrecognizedRecoveryMaterial_Should_NeverBeRecursivelyPruned' `
    -Arrange {
        $root = New-GitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        $directory = Join-Path (Get-ProjectStateDir -TargetPath $root) 'backups\unrecognized-generation'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $path = Join-Path $directory 'unrecorded-original.txt'
        Set-Content -LiteralPath $path -Value 'UNCONSUMED ORIGINAL - NO MANIFEST POINTER'
        [pscustomobject]@{ Root = $root; Path = $path; Hash = (Get-Sha256TestFileHash -Path $path) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.Hash -or
            -not (Test-Path -LiteralPath (Get-ProjectManifestPath -TargetPath $ctx.Root))) {
            throw 'Unrecognized recovery material was recursively discarded.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root -BackupPaths @($ctx.Path)
    }

foreach ($ignoreProfile in @('ManagedDirectory', 'NarrowForeign', 'ChildrenWithNegation')) {
Test-Case -Name "H04_H06_StateNamespace_PersonalRestorationStaging_${ignoreProfile}_Should_BeCompletelyIgnored" `
    -Arrange {
        if ($ignoreProfile -eq 'ManagedDirectory') { return New-ProjectOriginalFixture -Name 'local-preferences.instructions.md' }
        $root = New-GitFixtureRoot
        $path = Join-Path (Get-InstructionsDir -TargetPath $root) 'local-preferences.instructions.md'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $path -Value 'PERSONAL ORIGINAL FOR WHOLE-NAMESPACE EXCLUSION' -Encoding utf8 -NoNewline
        $hash = Get-Sha256TestFileHash -Path $path
        $rules = "$script:GitignoreEntry`n/.np-copilot-project-installer/manifest.json`n/.np-copilot-project-installer/backups/`n"
        if ($ignoreProfile -eq 'ChildrenWithNegation') {
            $rules = "$script:GitignoreEntry`n/.np-copilot-project-installer/*`n!/.np-copilot-project-installer/.np-restore-*`n"
        }
        Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value $rules -Encoding utf8 -NoNewline
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root -ExtraArgs @('-Force'))
        $manifest = Import-ProjectTestManifest -TargetPath $root
        [pscustomobject]@{ Root = $root; Path = $path; OriginalHash = $hash; ForeignRules = $rules
            BackupPath = @($manifest.Artifacts | Where-Object Name -EQ 'local-preferences.instructions.md')[0].BackupPath }
    } `
    -Act {
        param($ctx)
        $sourceId = 'np-project-restore-' + [guid]::NewGuid().ToString('N')
        $watcher = [IO.FileSystemWatcher]::new($ctx.Root, '.np-restore-*.tmp')
        $watcher.IncludeSubdirectories = $true
        Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier $sourceId | Out-Null
        $watcher.EnableRaisingEvents = $true
        $lock = [IO.File]::Open($ctx.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $event = Wait-Event -SourceIdentifier $sourceId -Timeout 5
            if (-not $event) { throw 'The real restoration did not produce an observable staging creation.' }
            $events = @(Get-Event | Where-Object SourceIdentifier -EQ $sourceId)
            foreach ($created in $events) {
                $path = $created.SourceEventArgs.FullPath
                $state = Get-ProjectStateDir -TargetPath $ctx.Root
                if (-not $path.StartsWith($state + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Personal restore bytes were staged outside ignored installer state: '$path'."
                }
                $relative = [IO.Path]::GetRelativePath($ctx.Root, $path).Replace('\', '/')
                $ignored = Invoke-ProjectFixtureGit -Root $ctx.Root -Arguments @('check-ignore', '--quiet', '--no-index', '--', $relative)
                if ($ignored.ExitCode -ne 0) {
                    throw "Actual Git rules left personal staging unignored: '$relative' (git check-ignore exit $($ignored.ExitCode))."
                }
            }
        }
        finally {
            $lock.Dispose()
            $watcher.Dispose()
            Unregister-Event -SourceIdentifier $sourceId
            foreach ($event in @(Get-Event | Where-Object SourceIdentifier -EQ $sourceId)) { Remove-Event -EventIdentifier $event.EventIdentifier }
        }
        $stateIgnored = Invoke-ProjectFixtureGit -Root $ctx.Root -Arguments @('check-ignore', '--quiet', '--no-index', '--', $script:StateDirName)
        if ($stateIgnored.ExitCode -ne 0) { throw 'The actual state directory itself was not excluded.' }
        foreach ($relative in @("$script:StateDirName/future-personal-copy", "$script:StateDirName/arbitrary/nested/private-copy")) {
            $ignored = Invoke-ProjectFixtureGit -Root $ctx.Root -Arguments @('check-ignore', '--quiet', '--no-index', '--', $relative)
            if ($ignored.ExitCode -ne 0) { throw "The state namespace is not protected: '$relative'." }
        }
        if ($ctx.PSObject.Properties.Name -contains 'ForeignRules') {
            $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
            if (-not $manifest.GitignoreManaged -or -not $manifest.GitignoreEffective -or $manifest.GitignoreBlocks.Count -ne 1) {
                throw 'Partial foreign rules were treated as complete protection instead of adding one owned directory exclusion.'
            }
            if (-not [IO.File]::ReadAllText((Join-Path $ctx.Root '.gitignore')).StartsWith($ctx.ForeignRules, [StringComparison]::Ordinal)) {
                throw 'Repair of incomplete exclusions changed or adopted the foreign rules.'
            }
        }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Observed staging/retry did not preserve the personal original.' }
    }
}

Test-Case -Name 'H06_StateNamespace_SkipAndWhatIf_Should_NotClaimSampledRulesProtectTheDirectory' `
    -Arrange {
        $root = New-GitFixtureRoot
        $rules = "$script:GitignoreEntry`n/.np-copilot-project-installer/manifest.json`n/.np-copilot-project-installer/backups/`n"
        Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value $rules -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; Rules = $rules; Before = (Get-ProjectFixtureSnapshot -Root $root) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-WhatIf'))
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Directory-type verification mutated the target in WhatIf mode.' }
        $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-SkipGitignore')
        Assert-ProjectRunSucceeded -Result $result
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.GitignoreEffective -or $manifest.GitignoreManaged) { throw 'Sampled rules were incorrectly reported as complete directory protection.' }
        if ($result.Output -notmatch 'may be exposed' -or $result.Output -match 'Git exclusions verified') {
            throw 'SkipGitignore did not report the incomplete state namespace accurately.'
        }
        $ctx
    } `
    -Assert {
        param($ctx)
        if ([IO.File]::ReadAllText((Join-Path $ctx.Root '.gitignore')) -cne $ctx.Rules) { throw 'SkipGitignore changed foreign rules.' }
    }

foreach ($missingSource in @('project-config.instructions.md', 'local-preferences.instructions.md')) {
    Test-Case -Name "M09_MissingSource_${missingSource}_Should_PreserveManifestAndOriginalRestorePoint" `
        -Arrange {
            $copy = New-InstallProjectScriptCopy
            $ctx = New-ProjectOriginalFixture -Name $missingSource -ScriptPath $copy.ScriptPath
            Remove-Item -LiteralPath (Join-Path $copy.TemplatesDir $missingSource)
            [pscustomobject]@{ Root = $ctx.Root; Fixture = $ctx; Copy = $copy; Before = (Get-ProjectFixtureSnapshot -Root $ctx.Root)
                CleanupPaths = @($ctx.Root, $copy.Root) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ScriptPath $ctx.Copy.ScriptPath -ExtraArgs @('-Force')) -Pattern 'Required template not found'
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'A missing source dropped or rewrote ownership/recovery state.' }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ScriptPath $ctx.Copy.ScriptPath -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.Fixture.Path) -cne $ctx.Fixture.OriginalHash) { throw 'Source omission made the original unrecoverable.' }
        }
}

foreach ($collisionName in @('project-config.instructions.md', 'local-preferences.instructions.md')) {
    Test-Case -Name "M10_DirectoryAt_${collisionName}_Should_RejectAllModesWithoutNestedCopies" `
        -Arrange {
            $root = New-GitFixtureRoot
            $collision = Join-Path (Get-InstructionsDir -TargetPath $root) $collisionName
            New-Item -ItemType Directory -Path $collision -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $collision 'sentinel.txt') -Value 'DO NOT REPLACE THIS DIRECTORY'
            [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
        } `
        -Act {
            param($ctx)
            foreach ($arguments in @(@(), @('-Force'), @('-WhatIf'), @('-Uninstall'))) {
                Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'Directory collision at file path'
            }
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'A directory collision was replaced, populated, or otherwise mutated.' }
        }
}

$ignoreCases = @(
    @{ Name = 'Comment'; Content = "# $script:GitignoreEntry"; AlreadyEffective = $false },
    @{ Name = 'Negation'; Content = "!$script:GitignoreEntry`n"; AlreadyEffective = $false },
    @{ Name = 'SuffixedPath'; Content = "$script:GitignoreEntry.backup`n"; AlreadyEffective = $false },
    @{ Name = 'ForeignLegacyBlock'; Content = "$script:GitignoreMarker`n$script:GitignoreEntry"; AlreadyEffective = $false },
    @{ Name = 'ForeignSuffixedBlock'; Content = "$script:GitignoreMarker`n$script:GitignoreEntry.suffix`n"; AlreadyEffective = $false },
    @{ Name = 'ForeignCompleteRules'; Content = "$script:GitignoreMarker`r`n$script:GitignoreEntry`r`n/.np-copilot-project-installer/`r`n"; AlreadyEffective = $true },
    @{ Name = 'AnchoredForeignRules'; Content = "/$script:GitignoreEntry`n/.np-copilot-project-installer/"; AlreadyEffective = $true },
    @{ Name = 'Utf8BomAndNoFinalNewline'; Content = ([string][char]0xFEFF + "# user-owned UTF-8 BOM`r`n$script:GitignoreEntry.suffix"); AlreadyEffective = $false }
)
foreach ($ignoreCase in $ignoreCases) {
    Test-Case -Name "M08_Ignore_$($ignoreCase.Name)_Should_VerifyGitEffectivenessAndPreserveForeignBytes" `
        -Arrange {
            $root = New-GitFixtureRoot
            $path = Join-Path $root '.gitignore'
            [IO.File]::WriteAllBytes($path, [Text.UTF8Encoding]::new($false).GetBytes($ignoreCase.Content))
            [pscustomobject]@{ Root = $root; Path = $path; OriginalHash = (Get-Sha256TestFileHash -Path $path)
                OriginalContent = $ignoreCase.Content; AlreadyEffective = $ignoreCase.AlreadyEffective }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
            $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
            if (-not $manifest.GitignoreEffective) { throw 'Manifest did not report the actual verified exclusion.' }
            if ($ctx.AlreadyEffective) {
                if ($manifest.GitignoreManaged -or $manifest.GitignoreBlocks.Count) { throw 'Existing effective foreign rules were adopted as installer-owned.' }
                if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Effective foreign rules were rewritten.' }
            }
            else {
                if (-not $manifest.GitignoreManaged -or $manifest.GitignoreBlocks.Count -ne 1) { throw 'Owned ignore insertion was not idempotent.' }
                if (-not [IO.File]::ReadAllText($ctx.Path).Contains($ctx.OriginalContent.TrimStart([char]0xFEFF))) {
                    throw 'Appending effective exclusions lost the foreign prefix.'
                }
            }
            Assert-ProjectPrivacy -Root $ctx.Root
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) {
                throw 'Uninstall removed foreign ignore text or failed complete-line/separator ownership boundaries.'
            }
        }
}

Test-Case -Name 'M08_LaterNegations_Should_BeRepairedOnceWithoutRemovingForeignRules' `
    -Arrange {
        $root = New-GitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        $path = Join-Path $root '.gitignore'
        $foreign = "!$script:GitignoreEntry`n!/.np-copilot-project-installer/`n"
        Add-Content -LiteralPath $path -Value $foreign -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; Path = $path; Foreign = $foreign }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        if ((Import-ProjectTestManifest -TargetPath $ctx.Root).GitignoreBlocks.Count -ne 2) {
            throw 'A later negation was not repaired with exactly one further owned insertion.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ([IO.File]::ReadAllText($ctx.Path) -cne $ctx.Foreign) { throw 'Complete-block removal changed the foreign negation lines.' }
    }

Test-Case -Name 'M08_H06_EditedOwnedBlock_Should_NotUseSubstringRemovalOrExposeRetainedState' `
    -Arrange {
        $root = New-GitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        $path = Join-Path $root '.gitignore'
        $edited = [IO.File]::ReadAllText($path).Replace($script:GitignoreEntry, "$script:GitignoreEntry.suffix")
        Set-Content -LiteralPath $path -Value $edited -Encoding utf8 -NoNewline
        [pscustomobject]@{ Root = $root; Path = $path; Edited = $edited }
    } `
    -Act {
        param($ctx)
        $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')
        Assert-ProjectRunSucceeded -Result $result
        if ($result.Output -notmatch 'edited or duplicated' -or $result.Output -match 'Uninstall complete') {
            throw 'An edited owned block was silently removed or reported as fully cleaned.'
        }
        $ctx
    } `
    -Assert {
        param($ctx)
        if (-not [IO.File]::ReadAllText($ctx.Path).StartsWith($ctx.Edited, [StringComparison]::Ordinal)) {
            throw 'An edited block was matched as an unbounded substring.'
        }
        Assert-ProjectPrivacy -Root $ctx.Root
        if (-not (Test-Path -LiteralPath (Get-ProjectManifestPath -TargetPath $ctx.Root))) { throw 'Edited ignore ownership was forgotten.' }
    }

Test-Case -Name 'H06_M08_OverridingNestedIgnore_Should_FailExplicitlyAndRollBackBeforePersonalWrites' `
    -Arrange {
        $root = New-GitFixtureRoot
        $directory = Get-InstructionsDir -TargetPath $root
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $directory '.gitignore') -Value '!local-preferences.instructions.md' -NoNewline
        Set-Content -LiteralPath (Join-Path $root '.gitignore') -Value '' -NoNewline
        [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
    } `
    -Act {
        param($ctx)
        $result = Invoke-InstallProject -TargetPath $ctx.Root
        Assert-ProjectRunFailed -Result $result -Pattern 'Effective Git exclusion could not be established'
        if ($result.Output -notmatch 'Reverted AppendedGitignore') { throw 'Failed privacy insertion was not rolled back.' }
        $ctx
    } `
    -Assert {
        param($ctx)
        if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $ctx.Root)) { throw 'Failed exclusion verification published state.' }
        if ([IO.File]::ReadAllText((Join-Path $ctx.Root '.gitignore')) -cne '') { throw 'The original empty ignore file was not restored.' }
        if (-not (Test-Path -LiteralPath (Join-Path $ctx.Root '.gitignore') -PathType Leaf)) { throw 'Rollback deleted a pre-existing empty ignore file.' }
        foreach ($name in @('project-config.instructions.md', 'local-preferences.instructions.md')) {
            if (Test-Path -LiteralPath (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) $name)) { throw 'Personal/template output was written before exclusion was verified.' }
        }
    }

Test-Case -Name 'M08_SkipGitignore_Should_WarnAccuratelyAndNeverClaimPrivateFilesAreIgnored' `
    -Arrange {
        $root = New-GitFixtureRoot
        New-Item -ItemType Directory -Path (Get-InstructionsDir -TargetPath $root) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path (Get-InstructionsDir -TargetPath $root) 'local-preferences.instructions.md') -Value 'PRIVATE ORIGINAL'
        $path = Join-Path $root '.gitignore'
        Set-Content -LiteralPath $path -Value "# $script:GitignoreEntry" -NoNewline
        [pscustomobject]@{ Root = $root; Path = $path; BeforeHash = (Get-Sha256TestFileHash -Path $path) }
    } `
    -Act {
        param($ctx)
        $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-SkipGitignore', '-Force')
        Assert-ProjectRunSucceeded -Result $result
        if ($result.Output -notmatch 'management skipped \(-SkipGitignore\)' -or
            $result.Output -match 'local-preferences is gitignored|Git exclusions verified') {
            throw 'SkipGitignore made a success-shaped privacy claim or omitted the warning.'
        }
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.GitignoreManaged -or $manifest.GitignoreEffective -or $manifest.GitignorePolicyEnabled) {
            throw 'Skipped ignore management was recorded as effective/owned.'
        }
        $git = Invoke-ProjectFixtureGit -Root $ctx.Root -Arguments @('check-ignore', '--quiet', '--no-index', '--', $script:GitignoreEntry)
        if ($git.ExitCode -ne 1) { throw 'Fixture did not exercise an actually unignored personal file.' }
        Set-Content -LiteralPath (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'local-preferences.instructions.md') -Value 'PRIVATE EDIT LEFT IN PLACE'
        $uninstall = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall')
        Assert-ProjectRunSucceeded -Result $uninstall
        if ($uninstall.Output -notmatch 'may still be exposed' -or $uninstall.Output -match 'Retained Git exclusions') {
            throw 'Partial skipped-ignore uninstall falsely claimed exclusion protection.'
        }
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.BeforeHash) { throw 'SkipGitignore mutated foreign ignore text.' }
    }

Test-Case -Name 'M08_ForceAndUninstallWhatIf_Should_LeaveEveryArtifactBackupManifestAndIgnoreByteUnchanged' `
    -Arrange { New-ProjectOriginalFixture -Name 'local-preferences.instructions.md' } `
    -Act {
        param($ctx)
        Set-Content -LiteralPath $ctx.Path -Value 'A NEW PERSONAL EDIT - DO NOT BACK UP IN WHATIF'
        $before = Get-ProjectFixtureSnapshot -Root $ctx.Root
        foreach ($arguments in @(@('-Force', '-WhatIf'), @('-Uninstall', '-WhatIf'), @('-SkipGitignore', '-Force', '-WhatIf'))) {
            $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments
            Assert-ProjectRunSucceeded -Result $result
            if ($result.Output -notmatch 'WhatIf: no changes were made' -or $result.Output -match 'Project templates installed|Uninstall complete|overwritten \(-Force\)|Restored previous content to') {
                throw 'Preview reported an operation as completed.'
            }
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $before) { throw 'Preview mutated fixture artifacts or recovery state.' }
        }
        $ctx
    } `
    -Assert { param($ctx) }

foreach ($ancestor in @('.github', '.github\instructions', '.np-copilot-project-installer')) {
    Test-Case -Name "H01_M10_ReparseAncestor_${ancestor}_Should_RejectWritesOutsideTheTarget" `
        -Arrange {
            $root = New-GitFixtureRoot
            $outside = New-NonGitFixtureRoot
            Set-Content -LiteralPath (Join-Path $outside 'sentinel') -Value 'OUTSIDE TARGET - DO NOT MUTATE'
            $link = Join-Path $root $ancestor
            $parent = Split-Path $link -Parent
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
            [pscustomobject]@{ Root = $root; Outside = $outside; Before = (Get-ProjectFixtureSnapshot -Root $root)
                OutsideBefore = (Get-ProjectFixtureSnapshot -Root $outside); CleanupPaths = @($root, $outside) }
        } `
        -Act {
            param($ctx)
            foreach ($arguments in @(@('-Force'), @('-Uninstall'), @('-WhatIf'))) {
                Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'Unsafe directory path'
            }
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before -or
                (Get-ProjectFixtureSnapshot -Root $ctx.Outside) -cne $ctx.OutsideBefore) { throw 'A reparse ancestor redirected a mutation outside the target.' }
        }
}

Test-Case -Name 'H01_BackupReparseAncestor_Should_RejectRestorationThroughAChangedPhysicalBoundary' `
    -Arrange {
        $ctx = New-ProjectOriginalFixture
        $outside = New-NonGitFixtureRoot
        $runDirectory = Split-Path $ctx.BackupPath -Parent
        $saved = Join-Path $outside 'original-backup-directory'
        Move-Item -LiteralPath $runDirectory -Destination $saved
        New-Item -ItemType Junction -Path $runDirectory -Target $saved | Out-Null
        [pscustomobject]@{ Root = $ctx.Root; Outside = $outside; Before = (Get-ProjectFixtureSnapshot -Root $ctx.Root)
            OutsideBefore = (Get-ProjectFixtureSnapshot -Root $outside); CleanupPaths = @($ctx.Root, $outside) }
    } `
    -Act {
        param($ctx)
        foreach ($arguments in @(@('-Force'), @('-Uninstall'))) {
            Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'Unsafe directory path'
        }
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before -or
            (Get-ProjectFixtureSnapshot -Root $ctx.Outside) -cne $ctx.OutsideBefore) { throw 'Backup restoration followed a redirected ancestor.' }
    }

Test-Case -Name 'H01_TargetRootReparse_Should_RejectAliasWithoutTouchingItsReferent' `
    -Arrange {
        $root = New-NonGitFixtureRoot
        $outside = New-GitFixtureRoot
        $alias = Join-Path $root 'repository-alias'
        New-Item -ItemType Junction -Path $alias -Target $outside | Out-Null
        [pscustomobject]@{ Root = $root; Alias = $alias; Outside = $outside; Before = (Get-ProjectFixtureSnapshot -Root $outside)
            CleanupPaths = @($root, $outside) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Alias -ExtraArgs @('-Force')) -Pattern 'Unsafe directory path'
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Outside) -cne $ctx.Before) { throw 'Target-root alias mutated its referent.' }
    }

Test-Case -Name 'H01_M10_FileSymlinkForceBackupAndRestore_Should_PreserveTheLinkEntryWithoutOwningItsReferent' `
    -Arrange {
        $root = New-GitFixtureRoot
        $outside = New-NonGitFixtureRoot
        $original = Join-Path $outside 'foreign-original.md'
        Set-Content -LiteralPath $original -Value 'FOREIGN LINK REFERENT - MUST NEVER RECEIVE TEMPLATE WRITES'
        $path = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $path -Target $original | Out-Null
        [pscustomobject]@{ Root = $root; Path = $path; Outside = $outside; Original = $original
            OutsideBefore = (Get-ProjectFixtureSnapshot -Root $outside); CleanupPaths = @($root, $outside) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        if ((Import-ProjectTestManifest -TargetPath $ctx.Root).Artifacts[0].Status -cne 'Conflict') { throw 'A foreign file link was adopted without Force.' }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
        $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
        if ($manifest.Artifacts[0].BackupIdentity.Kind -cne 'SymbolicLink') { throw 'Force followed the original link instead of backing up its entry.' }
        if ((Get-Item -LiteralPath $ctx.Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Force wrote through a link instead of replacing the entry.' }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        $entry = Get-Item -LiteralPath $ctx.Path -Force
        if ($entry.LinkType -cne 'SymbolicLink' -or [string]$entry.Target -cne $ctx.Original) { throw 'Original link identity was not restored.' }
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Outside) -cne $ctx.OutsideBefore) { throw 'A foreign link referent was mutated.' }
    }

Test-Case -Name 'H01_M10_UnexpectedManagedFileSymlink_Should_RemainAConflictEvenWhenReferentBytesMatch' `
    -Arrange {
        $root = New-GitFixtureRoot
        $outside = New-NonGitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        $path = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        $foreign = Join-Path $outside 'matching-but-foreign.md'
        Copy-Item -LiteralPath $path -Destination $foreign
        Remove-Item -LiteralPath $path
        New-Item -ItemType SymbolicLink -Path $path -Target $foreign | Out-Null
        [pscustomobject]@{ Root = $root; Path = $path; Outside = $outside; OutsideBefore = (Get-ProjectFixtureSnapshot -Root $outside)
            CleanupPaths = @($root, $outside) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Item -LiteralPath $ctx.Path -Force).LinkType -cne 'SymbolicLink') { throw 'Uninstall removed a replacement foreign link by comparing referent hashes.' }
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Outside) -cne $ctx.OutsideBefore) { throw 'Uninstall wrote a foreign referent.' }
        if (-not (Test-Path -LiteralPath (Get-ProjectManifestPath -TargetPath $ctx.Root))) { throw 'Topology drift lost its recovery record.' }
    }

foreach ($linkMode in @('Relative', 'Dangling')) {
    Test-Case -Name "H01_H04_${linkMode}FileSymlink_Should_PreserveItsRawRestoreTarget" `
        -Arrange {
            $root = New-GitFixtureRoot
            $directory = Get-InstructionsDir -TargetPath $root
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $referent = Join-Path $root 'original.md'
            if ($linkMode -eq 'Relative') { Set-Content -LiteralPath $referent -Value 'RELATIVE LINK ORIGINAL' }
            $path = Join-Path $directory 'project-config.instructions.md'
            $rawTarget = '..\..\original.md'
            New-Item -ItemType SymbolicLink -Path $path -Target $rawTarget | Out-Null
            [pscustomobject]@{ Root = $root; Path = $path; RawTarget = $rawTarget; Referent = $referent
                ReferentHash = (Get-Sha256TestFileHash -Path $referent) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
            $artifact = (Import-ProjectTestManifest -TargetPath $ctx.Root).Artifacts[0]
            if ($artifact.BackupIdentity.Kind -cne 'SymbolicLink' -or $artifact.BackupIdentity.LinkTarget -cne $ctx.RawTarget) {
                throw 'A relative/dangling link was read as content or persisted with a rewritten target.'
            }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            $entry = Get-Item -LiteralPath $ctx.Path -Force
            if ($entry.LinkType -cne 'SymbolicLink' -or [string]$entry.Target -cne $ctx.RawTarget) {
                throw 'Original raw link target was not restored.'
            }
            if ((Get-Sha256TestFileHash -Path $ctx.Referent) -cne $ctx.ReferentHash) { throw 'Restoration wrote or created the link referent.' }
        }
}

Test-Case -Name 'C11_HardLinkedFile_Should_BeReplacedAsAnEntryAndRestoredAsAnIndependentSnapshot' `
    -Arrange {
        $root = New-GitFixtureRoot
        $outside = New-NonGitFixtureRoot
        $original = Join-Path $outside 'hard-link-original.md'
        Set-Content -LiteralPath $original -Value 'HARD-LINK ORIGINAL - NO SHARED TEMPLATE WRITES'
        $path = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        New-Item -ItemType HardLink -Path $path -Target $original | Out-Null
        [pscustomobject]@{ Root = $root; Path = $path; Outside = $outside; Original = $original
            OriginalHash = (Get-Sha256TestFileHash -Path $original); CleanupPaths = @($root, $outside) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
        if ((Get-Sha256TestFileHash -Path $ctx.Original) -cne $ctx.OriginalHash) { throw 'Force wrote through a hard-link alias.' }
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
        Set-Content -LiteralPath $ctx.Original -Value 'INDEPENDENT POST-RESTORE ALIAS EDIT'
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Restored snapshot unexpectedly retained shared-write aliasing.' }
    }

Test-Case -Name 'H02_AtomicPublishFailure_Should_RollBackNewDirectoriesAndPreservePriorManifestBytes' `
    -Arrange {
        $root = New-GitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        $github = Join-Path $root '.github'
        Remove-Item -LiteralPath $github -Recurse -Force
        [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root)
            ManifestPath = (Get-ProjectManifestPath -TargetPath $root) }
    } `
    -Act {
        param($ctx)
        $lock = [IO.File]::Open($ctx.ManifestPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $result = Invoke-InstallProject -TargetPath $ctx.Root
            Assert-ProjectRunFailed -Result $result -Pattern 'Install step failed'
            if ($result.Output -notmatch 'Reverted CreatedDirectory' -or $result.Output -notmatch 'Reverted WroteFile') {
                throw 'Publication failure did not exercise rollback of new files and directories.'
            }
        }
        finally { $lock.Dispose() }
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Failed publication left untracked template output or changed prior manifest bytes.' }
    }

foreach ($variant in @('Generic', 'Angular', 'Blazor', 'ServiceFabric')) {
    Test-Case -Name "C04_RootCapabilityOwner_${variant}_Should_EmitOnlyAReferenceIncludingAfterForce" `
        -Arrange {
            $root = New-GitFixtureRoot
            New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
            $path = Join-Path $root '.github\copilot-instructions.md'
            $contract = "# Project`n`n## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Verified human-approved PR path |`n"
            Set-Content -LiteralPath $path -Value $contract -Encoding utf8 -NoNewline
            [pscustomobject]@{ Root = $root; Path = $path; OriginalHash = (Get-Sha256TestFileHash -Path $path) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Template', $variant))
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Template', $variant, '-Force'))
            $ctx
        } `
        -Assert {
            param($ctx)
            Assert-ProjectRootCapabilityReference -Path (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md')
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Installer modified the root capability contract.' }
        }
}

foreach ($legacyOwner in @($false, $true)) {
    Test-Case -Name "C04_ProjectCapabilityOwner_Legacy_${legacyOwner}_Should_PreserveVerifiedValuesDuringForceAndRefresh" `
        -Arrange {
            $copy = New-InstallProjectScriptCopy
            $root = New-GitFixtureRoot
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root -ScriptPath $copy.ScriptPath)
            $path = Join-Path (Get-InstructionsDir -TargetPath $root) 'project-config.instructions.md'
            $content = [IO.File]::ReadAllText($path).Replace('| Remote delivery | No | |', '| Remote delivery | Yes | Verified repository delivery path |')
            if ($legacyOwner) {
                $content = $content.Replace('<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->', '')
            }
            Set-Content -LiteralPath $path -Value $content -Encoding utf8 -NoNewline
            $rootReference = "## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->`n`nSee [project-config](instructions/project-config.instructions.md#agent-delivery-capabilities).`n"
            Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value $rootReference -Encoding utf8 -NoNewline
            [pscustomobject]@{ Root = $root; Path = $path; Copy = $copy; CleanupPaths = @($root, $copy.Root) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ScriptPath $ctx.Copy.ScriptPath -ExtraArgs @('-Force', '-Template', 'Angular'))
            $sourcePath = Join-Path $ctx.Copy.TemplatesDir 'project-config-angular.instructions.md'
            Add-Content -LiteralPath $sourcePath -Value "`nREFRESHED ANGULAR SOURCE"
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ScriptPath $ctx.Copy.ScriptPath -ExtraArgs @('-Template', 'Angular'))
            $ctx
        } `
        -Assert {
            param($ctx)
            $content = [IO.File]::ReadAllText($ctx.Path)
            if ($content -notmatch '\| Remote delivery \| Yes \| Verified repository delivery path \|' -or
                $content -notmatch 'REFRESHED ANGULAR SOURCE' -or
                ([regex]::Matches($content, '<!-- np-copilot-capabilities-owner:')).Count -ne 1) {
                throw 'Force/template refresh lost the existing verified capability owner or duplicated its marker.'
            }
        }
}

Test-Case -Name 'C04_LegacyRootCapabilityTable_Should_RemainTheSingleOwner' `
    -Arrange {
        $root = New-GitFixtureRoot
        New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
        $path = Join-Path $root '.github\copilot-instructions.md'
        Set-Content -LiteralPath $path -Value @'
## Agent Delivery Capabilities

| Capability | Enabled | Repository-specific rule |
|---|---|---|
| Remote delivery | Yes | Verified legacy root-owned rule |
'@ -Encoding utf8
        [pscustomobject]@{ Root = $root; Path = $path; Hash = (Get-Sha256TestFileHash -Path $path) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
        $ctx
    } `
    -Assert {
        param($ctx)
        $config = [IO.File]::ReadAllText((Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md'))
        if ($config -match '(?m)^\| Capability \|' -or
            $config -notmatch 'np-copilot-capabilities-owner: \.github/copilot-instructions.md' -or
            $config -notmatch '\[root project contract\]\(\.\./copilot-instructions\.md\)') {
            throw 'An unmarked legacy root table was overridden with default-disabled capabilities.'
        }
        if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.Hash) { throw 'Legacy root declaration changed.' }
    }

Test-Case -Name 'C04_MissingReferencedCapabilityOwner_Should_FailInsteadOfCreatingDefaultDeclarations' `
    -Arrange {
        $root = New-GitFixtureRoot
        New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
        Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value "## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->`n`nSee project-config.`n"
        [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force')) -Pattern 'reference has no declaration'
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Missing capability owner was replaced by defaults.' }
    }

foreach ($contractName in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
    foreach ($declarationShape in @('Table', 'Prose')) {
        Test-Case -Name "C04_AlternateRoot_${contractName}_${declarationShape}_Should_BlockCompetingDefaultsUntilOwnershipIsResolved" `
            -Arrange {
                $root = New-GitFixtureRoot
                $content = if ($declarationShape -eq 'Table') {
                    "# Existing contract`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Preserve verified delivery rule |`n"
                }
                else { "# Existing contract`n`n### Delivery capabilities`nRemote delivery is enabled using the verified human handoff path.`n" }
                Set-Content -LiteralPath (Join-Path $root $contractName) -Value $content -Encoding utf8 -NoNewline
                [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
            } `
            -Act {
                param($ctx)
                foreach ($arguments in @(@(), @('-Force'), @('-WhatIf'))) {
                    Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments) -Pattern 'explicit reference/migration plan'
                }
                $ctx
            } `
            -Assert {
                param($ctx)
                if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) {
                    throw 'An unrepresented root capability owner received a competing default declaration or was mutated.'
                }
            }
    }
    foreach ($canonicalOwner in @('.github/instructions/project-config.instructions.md', '.github/copilot-instructions.md')) {
        Test-Case -Name "C04_AlternateRoot_${contractName}_Referencing_${canonicalOwner}_Should_PreserveTheCanonicalOwner" `
            -Arrange {
                $root = New-GitFixtureRoot
                $ownerPath = Join-Path $root $canonicalOwner.Replace('/', '\')
                New-Item -ItemType Directory -Path (Split-Path $ownerPath -Parent) -Force | Out-Null
                $heading = if ($canonicalOwner -eq '.github/copilot-instructions.md') { 'Delivery capabilities' } else { 'Agent Delivery Capabilities' }
                $content = "## $heading`n`n<!-- np-copilot-capabilities-owner: $canonicalOwner -->`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Existing canonical delivery rule |`n"
                Set-Content -LiteralPath $ownerPath -Value $content -Encoding utf8 -NoNewline
                $referencePath = Join-Path $root $contractName
                Set-Content -LiteralPath $referencePath -Value "## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: $canonicalOwner -->`n`nSee [the authoritative declaration]($canonicalOwner).`n" -Encoding utf8 -NoNewline
                [pscustomobject]@{ Root = $root; Owner = $canonicalOwner; ReferencePath = $referencePath
                    ReferenceHash = (Get-Sha256TestFileHash -Path $referencePath) }
            } `
            -Act {
                param($ctx)
                Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
                Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
                $ctx
            } `
            -Assert {
                param($ctx)
                if ((Get-Sha256TestFileHash -Path $ctx.ReferencePath) -cne $ctx.ReferenceHash) { throw 'Installer changed a foreign root-contract reference.' }
                $project = [IO.File]::ReadAllText((Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md'))
                if (-not $project.Contains("<!-- np-copilot-capabilities-owner: $($ctx.Owner) -->")) { throw 'Canonical owner marker was changed.' }
                if ($ctx.Owner -eq '.github/copilot-instructions.md' -and $project -match '(?m)^\| Capability \|') {
                    throw 'A reference to the root owner was replaced by a second table.'
                }
                if ($ctx.Owner -eq '.github/instructions/project-config.instructions.md' -and
                    $project -notmatch '\| Remote delivery \| Yes \| Existing canonical delivery rule \|') {
                    throw 'Existing project-config capabilities were reset.'
                }
            }
    }
}

foreach ($badMarker in @('<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md ->',
        '<!-- NP-COPILOT-CAPABILITIES-OWNER: .github/copilot-instructions.md -->')) {
    Test-Case -Name "C04_MalformedOwner_$($badMarker.Substring(5, 8))_Should_FailBeforeMutation" `
        -Arrange {
            $root = New-GitFixtureRoot
            New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
            $content = "## Delivery capabilities`n`n$badMarker`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Preserve this rule |`n"
            Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value $content -Encoding utf8 -NoNewline
            [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force')) -Pattern 'Malformed capability-owner marker'
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Malformed ownership metadata was silently reinterpreted.' }
        }
}

Test-Case -Name 'C04_ConflictingExplicitCapabilityOwners_Should_FailBeforeAnyMutationEvenWithForce' `
    -Arrange {
        $root = New-GitFixtureRoot
        Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root)
        Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value @'
## Delivery capabilities

<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->
| Capability | Enabled | Repository-specific rule |
|---|---|---|
| Remote delivery | Yes | Root verified rule |
'@ -Encoding utf8
        [pscustomobject]@{ Root = $root; Before = (Get-ProjectFixtureSnapshot -Root $root) }
    } `
    -Act {
        param($ctx)
        Assert-ProjectRunFailed -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force')) -Pattern 'Conflicting delivery-capability owners'
        $ctx
    } `
    -Assert {
        param($ctx)
        if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'Conflicting capability declarations were silently overwritten.' }
    }

foreach ($bomHeading in @('Delivery capabilities', 'Agent Delivery Capabilities')) {
    foreach ($markedBomOwner in @($false, $true)) {
        Test-Case -Name "C04_BOM_Root_${bomHeading}_Marked_${markedBomOwner}_Should_KeepVerifiedCapabilitiesAndOriginalBytes" `
            -Arrange {
                $root = New-GitFixtureRoot
                New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
                $path = Join-Path $root '.github\copilot-instructions.md'
                $marker = if ($markedBomOwner) { "<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`n`n" } else { '' }
                $text = [string][char]0xFEFF + "## $bomHeading`n`n$marker| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Preserve this verified BOM-root rule |`n"
                [IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes($text))
                [pscustomobject]@{ Root = $root; Path = $path; OriginalHash = (Get-Sha256TestFileHash -Path $path) }
            } `
            -Act {
                param($ctx)
                foreach ($arguments in @(@(), @('-Force', '-Template', 'Angular'))) {
                    Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs $arguments)
                    Assert-ProjectRootCapabilityReference -Path (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md')
                    if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.OriginalHash) { throw 'Parsing rewrote the BOM-bearing root owner.' }
                }
                $ctx
            } `
            -Assert {
                param($ctx)
                if ([IO.File]::ReadAllText($ctx.Path) -notmatch '\| Remote delivery \| Yes \| Preserve this verified BOM-root rule \|') {
                    throw 'The verified BOM-root capability value or rule was lost.'
                }
            }
    }
}

foreach ($markedBomProject in @($false, $true)) {
    Test-Case -Name "C04_BOM_ProjectOwner_Marked_${markedBomProject}_Should_PreserveForeignBytesValuesAndRestorePoint" `
        -Arrange {
            $root = New-GitFixtureRoot
            $directory = Get-InstructionsDir -TargetPath $root
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $path = Join-Path $directory 'project-config.instructions.md'
            $marker = if ($markedBomProject) { "<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->`n`n" } else { '' }
            $text = [string][char]0xFEFF + "## Agent Delivery Capabilities`n`n$marker| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Preserve this BOM-project rule |`n"
            [IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes($text))
            $referencePath = Join-Path $root '.github\copilot-instructions.md'
            Set-Content -LiteralPath $referencePath -Value "## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->`nSee [the owner](instructions/project-config.instructions.md).`n" -Encoding utf8 -NoNewline
            [pscustomobject]@{ Root = $root; Path = $path; Hash = (Get-Sha256TestFileHash -Path $path)
                ReferencePath = $referencePath; ReferenceHash = (Get-Sha256TestFileHash -Path $referencePath) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root)
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.Hash) { throw 'Non-Force parsing changed the original BOM bytes.' }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force'))
            $manifest = Import-ProjectTestManifest -TargetPath $ctx.Root
            $artifact = @($manifest.Artifacts | Where-Object Name -EQ 'project-config.instructions.md')[0]
            if ((Get-Sha256TestFileHash -Path $artifact.BackupPath) -cne $ctx.Hash) { throw 'Force did not preserve the original BOM-bearing restore point.' }
            $generated = [IO.File]::ReadAllText($ctx.Path)
            if ($generated -notmatch '\| Remote delivery \| Yes \| Preserve this BOM-project rule \|' -or
                $generated.Contains([char]0xFEFF)) { throw 'Capability preservation lost values or inserted a BOM into the middle of generated content.' }
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Uninstall'))
            $ctx
        } `
        -Assert {
            param($ctx)
            if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.Hash -or
                (Get-Sha256TestFileHash -Path $ctx.ReferencePath) -cne $ctx.ReferenceHash) {
                throw 'Uninstall or ownership parsing changed original bytes/reference content.'
            }
        }
}

foreach ($bomContract in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')) {
    foreach ($bomShape in @('Table', 'Heading', 'Reference')) {
        Test-Case -Name "C04_BOM_Alternate_${bomContract}_${bomShape}_Should_RespectItsExistingOwner" `
            -Arrange {
                $root = New-GitFixtureRoot
                $body = switch ($bomShape) {
                    'Table' { "| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Existing alternate-owner rule |`n" }
                    'Heading' { "### Delivery capabilities`nRemote delivery is enabled with the existing verified rule.`n" }
                    'Reference' {
                        New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
                        Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value "## Delivery capabilities`n`n<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Canonical root rule |`n" -Encoding utf8 -NoNewline
                        "<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->`nSee [the owner](.github/copilot-instructions.md).`n"
                    }
                }
                $path = Join-Path $root $bomContract
                [IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes(([string][char]0xFEFF + $body)))
                [pscustomobject]@{ Root = $root; Path = $path; Hash = (Get-Sha256TestFileHash -Path $path)
                    Before = (Get-ProjectFixtureSnapshot -Root $root); Shape = $bomShape }
            } `
            -Act {
                param($ctx)
                $result = Invoke-InstallProject -TargetPath $ctx.Root -ExtraArgs @('-Force')
                if ($ctx.Shape -eq 'Reference') {
                    Assert-ProjectRunSucceeded -Result $result
                    Assert-ProjectRootCapabilityReference -Path (Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md')
                }
                else {
                    Assert-ProjectRunFailed -Result $result -Pattern 'explicit reference/migration plan'
                    if ((Get-ProjectFixtureSnapshot -Root $ctx.Root) -cne $ctx.Before) { throw 'A BOM hid an alternate owner and allowed mutation.' }
                }
                $ctx
            } `
            -Assert {
                param($ctx)
                if ((Get-Sha256TestFileHash -Path $ctx.Path) -cne $ctx.Hash) { throw 'A BOM-bearing alternate contract/reference was rewritten.' }
            }
    }
}

foreach ($bomTemplateShape in @('WholeTemplate', 'CapabilityFirst')) {
    Test-Case -Name "C04_BOM_SourceTemplate_${bomTemplateShape}_Should_PreserveByteOffsetsDuringReferenceRendering" `
        -Arrange {
            $copy = New-InstallProjectScriptCopy
            $a = New-GitFixtureRoot
            $b = New-GitFixtureRoot
            foreach ($root in @($a, $b)) {
                New-Item -ItemType Directory -Path (Join-Path $root '.github') | Out-Null
                Set-Content -LiteralPath (Join-Path $root '.github\copilot-instructions.md') -Value "## Delivery capabilities`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | Yes | Preserve root ownership |`n" -Encoding utf8 -NoNewline
            }
            $source = Join-Path $copy.TemplatesDir 'project-config.instructions.md'
            if ($bomTemplateShape -eq 'CapabilityFirst') {
                Set-Content -LiteralPath $source -Value "## Agent Delivery Capabilities`n`n| Capability | Enabled | Repository-specific rule |`n|---|---|---|`n| Remote delivery | No | Template default |`n`n## Agent Guidance`nPRESERVE THIS SUFFIX`n" -Encoding utf8 -NoNewline
            }
            [pscustomobject]@{ Root = $a; B = $b; Copy = $copy; Source = $source; CleanupPaths = @($a, $b, $copy.Root) }
        } `
        -Act {
            param($ctx)
            Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.Root -ScriptPath $ctx.Copy.ScriptPath)
            $plain = [IO.File]::ReadAllBytes((Join-Path (Get-InstructionsDir -TargetPath $ctx.Root) 'project-config.instructions.md'))
            $sourceBytes = [IO.File]::ReadAllBytes($ctx.Source)
            [IO.File]::WriteAllBytes($ctx.Source, [byte[]](@(0xEF, 0xBB, 0xBF) + $sourceBytes))
            foreach ($arguments in @(@(), @('-Force'))) {
                Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $ctx.B -ScriptPath $ctx.Copy.ScriptPath -ExtraArgs $arguments)
                $actual = [IO.File]::ReadAllBytes((Join-Path (Get-InstructionsDir -TargetPath $ctx.B) 'project-config.instructions.md'))
                $expected = [byte[]](@(0xEF, 0xBB, 0xBF) + $plain)
                if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($expected)) {
                    throw 'Parsing normalization shifted raw replacement offsets or destroyed the source BOM/prefix/suffix.'
                }
            }
            $ctx
        } `
        -Assert { param($ctx) }
}

Test-Case -Name 'C01_C03_C04_C05_C11_Templates_Should_DeclareCompatibilitySingleOwnershipAndPluginBoundaries' `
    -Arrange { $null } `
    -Act {
        foreach ($path in Get-ChildItem -LiteralPath $script:TemplatesDir -Filter '*.instructions.md' -File) {
            $content = [IO.File]::ReadAllText($path.FullName)
            if ($content -notmatch '\A---\r?\napplyTo: "\*\*"\r?\n---\r?\n') { throw "Expected documented scalar applyTo in '$($path.Name)'." }
        }
        $bootstrap = [IO.File]::ReadAllText((Join-Path $script:TemplatesDir 'repo-bootstrap\copilot-instructions.template.md'))
        if ($bootstrap -notmatch '\{\{DELIVERY_CAPABILITIES_SECTION\}\}' -or $bootstrap -match '\{\{REMOTE_DELIVERY_ENABLED\}\}') {
            throw 'Root bootstrap template still requires a second capability table.'
        }
        foreach ($relative in @('repo-bootstrap\copilot-instructions.template.md', 'repo-bootstrap\docs\handoffs\README.md')) {
            $content = [IO.File]::ReadAllText((Join-Path $script:TemplatesDir $relative))
            if ($content -notmatch 'np-agent-memory' -or $content -notmatch 'unsolicited' -or
                $content -notmatch 'existing required project/cross-agent' -or $content -notmatch 'registration') {
                throw "Missing plugin ownership or existing-artifact boundary in '$relative'."
            }
        }
        $readme = [IO.File]::ReadAllText((Join-Path $script:TemplatesDir 'repo-bootstrap\README.md'))
        if ($readme -notmatch 'Distributing only' -or $readme -notmatch 'not supported' -or $readme -notmatch 'do not infer|Do not infer') {
            throw 'Bootstrap distribution/discovery boundaries were not documented.'
        }
    } `
    -Assert { param($ctx) }
