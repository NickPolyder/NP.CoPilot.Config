$ErrorActionPreference = 'Stop'

function Assert-InstallSuccess {
    param([Parameter(Mandatory)]$Result)
    if ($Result.ExitCode -ne 0) { throw "Expected success: $($Result.Output)" }
}

function Assert-InstallFailure {
    param([Parameter(Mandatory)]$Result)
    if ($Result.ExitCode -eq 0) { throw "Expected an explicit failure: $($Result.Output)" }
}

function Get-FixtureSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    $entries = [System.Collections.Generic.List[object]]::new()
    $directories = [System.Collections.Generic.Stack[string]]::new()
    $directories.Push($Root)
    while ($directories.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $directories.Pop() -Force) {
            $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName)
            if ($item.LinkType -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                $entries.Add([ordered]@{ Path = $relative; Kind = $item.LinkType; Target = @($item.Target) })
            }
            elseif ($item.PSIsContainer) {
                $entries.Add([ordered]@{ Path = $relative; Kind = 'Directory' })
                $directories.Push($item.FullName)
            }
            else {
                $entries.Add([ordered]@{ Path = $relative; Kind = 'File'; Hash = (Get-FileHash -LiteralPath $item.FullName).Hash })
            }
        }
    }
    ConvertTo-Json -InputObject @($entries | Sort-Object { $_.Path }) -Depth 8 -Compress
}

Test-Case -Name 'Manifest_Should_RejectCopiedTargetStateWithoutChangingEitherHome' `
    -Arrange {
        $a = New-FixtureRoot
        $b = New-FixtureRoot
        New-Item -ItemType Directory -Path (Join-Path $a 'instructions') | Out-Null
        Set-Content -LiteralPath (Join-Path $a 'instructions\original.txt') -Value 'original A'
        Assert-InstallSuccess (Invoke-Install $a)
        Copy-Item -LiteralPath (Join-Path $a '.np-copilot-installer') -Destination (Join-Path $b '.np-copilot-installer') -Recurse
        Set-Content -LiteralPath (Join-Path $b 'copilot-instructions.md') -Value 'original B'
        [pscustomobject]@{ A = $a; B = $b; BeforeA = Get-FixtureSnapshot $a; BeforeB = Get-FixtureSnapshot $b }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.B -ExtraArgs '-Uninstall' } } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Result
        if ($c.Result.Output -notmatch 'target does not match') { throw $c.Result.Output }
        if ((Get-FixtureSnapshot $c.Fixture.A) -ne $c.Fixture.BeforeA -or
            (Get-FixtureSnapshot $c.Fixture.B) -ne $c.Fixture.BeforeB) { throw 'A copied manifest changed a home.' }
    }

Test-Case -Name 'Manifest_Should_PersistAbsolutePathsAndIgnoreLaterWorkingDirectory' `
    -Arrange {
        $root = New-FixtureRoot
        $first = Join-Path $root 'first'
        $second = Join-Path $root 'second'
        New-Item -ItemType Directory -Path $first, $second | Out-Null
        Assert-InstallSuccess (Invoke-Install -TargetRoot 'copilot' -WorkingDirectory $first)
        Set-Content -LiteralPath (Join-Path $second 'sentinel.txt') -Value 'untouched'
        $target = Join-Path $first 'copilot'
        [pscustomobject]@{ Root = $root; Target = $target; Second = $second; Manifest = Import-Manifest $target }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Target -WorkingDirectory $f.Second -ExtraArgs '-Uninstall' } } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        foreach ($artifact in $c.Fixture.Manifest.Artifacts) {
            if (-not [System.IO.Path]::IsPathFullyQualified($artifact.TargetPath)) { throw 'Relative ownership path persisted.' }
        }
        if (Test-Path -LiteralPath (Get-ManifestPath $c.Fixture.Target)) { throw 'The intended installation was not removed.' }
        if ((Get-Content -LiteralPath (Join-Path $c.Fixture.Second 'sentinel.txt') -Raw).Trim() -ne 'untouched') { throw 'Wrong working directory changed.' }
    }

foreach ($invalidState in @('corrupt', 'schema', 'target-path', 'backup-path', 'duplicate', 'duplicate-case', 'wrong-backup-owner', 'missing-record-field')) {
    Test-Case -Name "Manifest_Should_FailClosedFor_$invalidState" `
        -Arrange {
            $root = New-FixtureRoot
            $foreign = New-FixtureRoot
            New-Item -ItemType Directory -Path (Join-Path $root 'instructions') | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'instructions\original.txt') -Value 'recover me'
            Set-Content -LiteralPath (Join-Path $foreign 'instructions') -Value 'foreign bytes'
            Assert-InstallSuccess (Invoke-Install $root)
            $path = Get-ManifestPath $root
            $manifest = Import-Manifest $root
            switch ($invalidState) {
                'corrupt' { Set-Content -LiteralPath $path -Value '{ invalid JSON' }
                'schema' { $manifest.SchemaVersion = 99 }
                'target-path' { $manifest.Artifacts[0].TargetPath = Join-Path $foreign 'copilot-instructions.md' }
                'backup-path' { $manifest.Artifacts[0].BackupPath = Join-Path $foreign 'instructions' }
                'duplicate' { $manifest.Artifacts += $manifest.Artifacts[0] }
                'duplicate-case' {
                    $copy = $manifest.Artifacts[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                    $copy.Name = $copy.Name.ToUpperInvariant()
                    $manifest.Artifacts += $copy
                }
                'wrong-backup-owner' {
                    $manifest.Artifacts[0].BackupPath = ($manifest.Artifacts | Where-Object Name -eq 'instructions').BackupPath
                }
                'missing-record-field' { $manifest.Artifacts[0].PSObject.Properties.Remove('BackupPath') }
            }
            if ($invalidState -ne 'corrupt') { $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path }
            [pscustomobject]@{ Root = $root; Foreign = $foreign; Before = Get-FixtureSnapshot $root; ForeignBefore = Get-FixtureSnapshot $foreign }
        } `
        -Act {
            param($f)
            $results = @(
                (Invoke-Install $f.Root)
                (Invoke-Install $f.Root -ExtraArgs '-Repair')
                (Invoke-Install $f.Root -ExtraArgs '-Status')
                (Invoke-Install $f.Root -ExtraArgs '-Uninstall')
            )
            [pscustomobject]@{ Fixture = $f; Results = $results }
        } `
        -Assert {
            param($c)
            foreach ($result in $c.Results) { Assert-InstallFailure $result }
            if ((Get-FixtureSnapshot $c.Fixture.Root) -ne $c.Fixture.Before -or
                (Get-FixtureSnapshot $c.Fixture.Foreign) -ne $c.Fixture.ForeignBefore) { throw 'Invalid state caused mutation.' }
        }
}

Test-Case -Name 'Manifest_Should_RejectLinkedStateDirectoryBeforeReadingForeignState' `
    -Arrange {
        $root = New-FixtureRoot
        $foreign = New-FixtureRoot
        Set-Content -LiteralPath (Join-Path $foreign 'sentinel.txt') -Value 'preserve'
        New-Item -ItemType SymbolicLink -Path (Join-Path $root '.np-copilot-installer') -Target $foreign | Out-Null
        [pscustomobject]@{ Root = $root; Foreign = $foreign; Before = Get-FixtureSnapshot $root; ForeignBefore = Get-FixtureSnapshot $foreign }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root } } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Result
        if ((Get-FixtureSnapshot $c.Fixture.Root) -ne $c.Fixture.Before -or
            (Get-FixtureSnapshot $c.Fixture.Foreign) -ne $c.Fixture.ForeignBefore) { throw 'Linked state escaped its boundary.' }
    }

Test-Case -Name 'Uninstall_Should_PreserveEarlierOriginalAcrossRepairGenerations' `
    -Arrange {
        $root = New-FixtureRoot
        $path = Join-Path $root 'instructions'
        New-Item -ItemType Directory -Path $path | Out-Null
        Set-Content -LiteralPath (Join-Path $path 'original-a.txt') -Value 'A'
        Assert-InstallSuccess (Invoke-Install $root)
        $first = (Import-Manifest $root).Artifacts | Where-Object Name -eq 'instructions'
        (Get-Item -LiteralPath $path -Force).Delete()
        New-Item -ItemType Directory -Path $path | Out-Null
        Set-Content -LiteralPath (Join-Path $path 'original-b.txt') -Value 'B'
        Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Repair')
        [pscustomobject]@{ Root = $root; FirstBackup = $first.BackupPath }
    } `
    -Act {
        param($f)
        $result = Invoke-Install $f.Root -ExtraArgs '-Uninstall'
        [pscustomobject]@{ Fixture = $f; Result = $result; Repair = Invoke-Install $f.Root -ExtraArgs '-Repair' }
    } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        Assert-InstallSuccess $c.Repair
        if (-not (Test-Path -LiteralPath (Join-Path $c.Fixture.Root 'instructions\original-b.txt'))) { throw 'Latest original was not restored.' }
        if (-not (Test-Path -LiteralPath (Join-Path $c.Fixture.FirstBackup 'original-a.txt'))) { throw 'Earlier original was discarded.' }
        $manifest = Import-Manifest $c.Fixture.Root
        if (@($manifest.Artifacts).Count -ne 0 -or $manifest.RecoveryPaths -notcontains $c.Fixture.FirstBackup) { throw 'Recovery-only state is inaccurate.' }
        if ((Get-Item -LiteralPath (Join-Path $c.Fixture.Root 'instructions')).LinkType) { throw 'Repair recreated an uninstalled artifact.' }
    }

Test-Case -Name 'Links_Should_RoundTripRelativeDirectoryLinkWithRawTargetIntact' `
    -Arrange {
        $root = New-FixtureRoot
        $target = Join-Path $root 'copilot'
        $foreign = Join-Path $root 'foreign'
        New-Item -ItemType Directory -Path $target, $foreign | Out-Null
        Set-Content -LiteralPath (Join-Path $foreign 'sentinel.txt') -Value 'relative original'
        New-Item -ItemType SymbolicLink -Path (Join-Path $target 'instructions') -Target '..\foreign' | Out-Null
        [pscustomobject]@{ Root = $root; Target = $target }
    } `
    -Act {
        param($f)
        Assert-InstallSuccess (Invoke-Install $f.Target)
        [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Target -ExtraArgs '-Uninstall' }
    } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        $item = Get-Item -LiteralPath (Join-Path $c.Fixture.Target 'instructions') -Force
        if ($item.LinkType -ne 'SymbolicLink' -or @($item.Target)[0] -ne '..\foreign') { throw 'Relative link metadata was changed.' }
        if ((Get-Content -LiteralPath (Join-Path $item.FullName 'sentinel.txt') -Raw).Trim() -ne 'relative original') { throw 'Relative referent changed.' }
    }

Test-Case -Name 'Rollback_Should_RestoreNonmatchingLinkInsideSourceTree' `
    -Arrange {
        $source = New-IsolatedSourceRoot
        $root = New-FixtureRoot
        $installer = Join-Path $source 'install.ps1'
        $foreign = Join-Path $source 'previous-location'
        New-Item -ItemType Directory -Path $foreign | Out-Null
        Set-Content -LiteralPath (Join-Path $foreign 'original.txt') -Value 'preserve this link'
        Assert-InstallSuccess (Invoke-Install $root -InstallScriptPath $installer)
        $path = Join-Path $root 'instructions'
        (Get-Item -LiteralPath $path -Force).Delete()
        New-Item -ItemType SymbolicLink -Path $path -Target $foreign | Out-Null
        [pscustomobject]@{ Root = $root; Installer = $installer; Foreign = $foreign; Before = Get-FixtureSnapshot $root }
    } `
    -Act {
        param($f)
        $lock = [System.IO.File]::Open((Get-ManifestPath $f.Root), 'Open', 'ReadWrite', 'Read')
        try { $result = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Repair' }
        finally { $lock.Dispose() }
        [pscustomobject]@{ Fixture = $f; Result = $result }
    } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Result
        if (-not (Test-IsSymlinkTo (Join-Path $c.Fixture.Root 'instructions') $c.Fixture.Foreign)) { throw 'Rollback lost a source-tree foreign link.' }
        if ((Get-Content -LiteralPath (Join-Path $c.Fixture.Foreign 'original.txt') -Raw).Trim() -ne 'preserve this link') { throw 'Referent bytes changed.' }
    }

Test-Case -Name 'McpUninstall_Should_NotFollowReplacementForeignSymlink' `
    -Arrange {
        $root = New-FixtureRoot
        $foreignRoot = New-FixtureRoot
        $path = Join-Path $root 'mcp-config.json'
        Set-Content -LiteralPath $path -Value '{"mcpServers":{}}' -NoNewline
        Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Mcp')
        $foreign = Join-Path $foreignRoot 'foreign.json'
        Copy-Item -LiteralPath $path -Destination $foreign
        Remove-Item -LiteralPath $path
        New-Item -ItemType SymbolicLink -Path $path -Target $foreign | Out-Null
        [pscustomobject]@{ Root = $root; Path = $path; Foreign = $foreign; Hash = (Get-FileHash -LiteralPath $foreign).Hash }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root -ExtraArgs '-Uninstall' } } `
    -Assert {
        param($c)
        if ((Get-FileHash -LiteralPath $c.Fixture.Foreign).Hash -ne $c.Fixture.Hash) { throw 'Foreign MCP referent was modified.' }
        if (-not (Test-IsSymlinkTo $c.Fixture.Path $c.Fixture.Foreign)) { throw 'Foreign MCP link was replaced.' }
        $manifest = Import-Manifest $c.Fixture.Root
        if (@($manifest.Artifacts).Count -ne 1 -or $manifest.Artifacts[0].Kind -ne 'McpMerge') { throw 'Unresolved topology was not tracked.' }
        if ($c.Result.Output -match 'Uninstall complete') { throw 'Unresolved foreign content was reported complete.' }
    }

Test-Case -Name 'McpUninstall_Should_PreserveLaterUserMetadataAndOriginalRecoveryCopy' `
    -Arrange {
        $root = New-FixtureRoot
        $path = Join-Path $root 'mcp-config.json'
        Set-Content -LiteralPath $path -Value '{"mcpServers":{},"metadata":"before"}' -NoNewline
        Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Mcp')
        $backup = ((Import-Manifest $root).Artifacts | Where-Object Name -eq 'mcp-config.json').BackupPath
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.metadata = 'after'
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        [pscustomobject]@{ Root = $root; Path = $path; Backup = $backup }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root -ExtraArgs '-Uninstall' } } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        $json = Get-Content -LiteralPath $c.Fixture.Path -Raw | ConvertFrom-Json
        if ($json.metadata -ne 'after' -or @($json.mcpServers.PSObject.Properties).Count -ne 0) { throw 'User metadata or owned-entry removal is incorrect.' }
        if ((Get-Content -LiteralPath $c.Fixture.Backup -Raw | ConvertFrom-Json).metadata -ne 'before') { throw 'Original recovery copy was discarded.' }
    }

foreach ($modifyRetired in @($false, $true)) {
    Test-Case -Name "McpSync_Should_ReconcileRetiredOwnership_Modified_$modifyRetired" `
        -Arrange {
            $source = New-IsolatedSourceRoot
            $root = New-FixtureRoot
            $installer = Join-Path $source 'install.ps1'
            $targetPath = Join-Path $root 'mcp-config.json'
            Set-Content -LiteralPath $targetPath -Value '{"mcpServers":{}}' -NoNewline
            Assert-InstallSuccess (Invoke-Install $root -InstallScriptPath $installer -ExtraArgs '-Mcp')
            $sourcePath = Join-Path $source 'mcp-config.json'
            $json = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
            $retired = @($json.mcpServers.PSObject.Properties.Name)[0]
            if ($modifyRetired) {
                $targetJson = Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json
                $targetJson.mcpServers.$retired | Add-Member -NotePropertyName customMarker -NotePropertyValue 'preserved'
                $targetJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $targetPath
            }
            $json.mcpServers.PSObject.Properties.Remove($retired)
            $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath
            [pscustomobject]@{ Root = $root; Installer = $installer; Path = $targetPath; Retired = $retired; Modified = $modifyRetired }
        } `
        -Act {
            param($f)
            Assert-InstallSuccess (Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Mcp')
            $afterSync = Get-Content -LiteralPath $f.Path -Raw | ConvertFrom-Json
            $result = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Uninstall'
            [pscustomobject]@{ Fixture = $f; Result = $result; AfterSync = $afterSync }
        } `
        -Assert {
            param($c)
            Assert-InstallSuccess $c.Result
            $f = $c.Fixture
            $final = Get-Content -LiteralPath $f.Path -Raw | ConvertFrom-Json
            if ($f.Modified) {
                if ($final.mcpServers.($f.Retired).customMarker -ne 'preserved') { throw 'Modified retired entry was lost.' }
                $artifact = (Import-Manifest $f.Root).Artifacts | Where-Object Name -eq 'mcp-config.json'
                if (-not $artifact.OwnedEntries.PSObject.Properties[$f.Retired]) { throw 'Retired conflict lost ownership history.' }
            }
            elseif ($c.AfterSync.mcpServers.PSObject.Properties[$f.Retired] -or $final.mcpServers.PSObject.Properties[$f.Retired]) {
                throw 'Unchanged retired entry survived reconciliation.'
            }
        }
}

foreach ($invalidJson in @('[]', '"scalar"', '{"mcpServers":[]}', '{"mcpServers":null}', '{"mcpServers":{"entry":false}}')) {
    Test-Case -Name "McpPreflight_Should_RejectInvalidShape_$invalidJson" `
        -Arrange {
            $root = New-FixtureRoot
            Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Value $invalidJson -NoNewline
            [pscustomobject]@{ Root = $root; Before = Get-FixtureSnapshot $root }
        } `
        -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root -ExtraArgs '-Mcp' } } `
        -Assert {
            param($c)
            Assert-InstallFailure $c.Result
            if ((Get-FixtureSnapshot $c.Fixture.Root) -ne $c.Fixture.Before) { throw 'Invalid JSON shape caused mutation.' }
        }
}

Test-Case -Name 'Status_Should_InspectLiveJsonAndMissingSourceRatherThanSavedHealth' `
    -Arrange {
        $source = New-IsolatedSourceRoot
        $root = New-FixtureRoot
        $installer = Join-Path $source 'install.ps1'
        Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Value '{"mcpServers":{}}' -NoNewline
        Assert-InstallSuccess (Invoke-Install $root -InstallScriptPath $installer -ExtraArgs '-Mcp')
        Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Value '{malformed-sensitive-content'
        Remove-Item -LiteralPath (Join-Path $source 'skills') -Recurse -Force
        [pscustomobject]@{ Root = $root; Installer = $installer }
    } `
    -Act { param($f) Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Status' } `
    -Assert {
        param($r)
        Assert-InstallSuccess $r
        if ($r.Output -notmatch 'mcp-config.json: Invalid MCP JSON' -or $r.Output -notmatch 'skills: Missing or invalid source') { throw $r.Output }
        if ($r.Output -match 'malformed-sensitive-content') { throw 'Status disclosed invalid JSON contents.' }
    }

Test-Case -Name 'Repair_Should_RespectPartialUninstallScopeWithoutReintroducingMcp' `
    -Arrange {
        $root = New-FixtureRoot
        Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Mcp')
        $path = Join-Path $root 'instructions'
        (Get-Item -LiteralPath $path -Force).Delete()
        New-Item -ItemType Directory -Path $path | Out-Null
        Set-Content -LiteralPath (Join-Path $path 'keep.txt') -Value 'keep'
        Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Uninstall')
        $root
    } `
    -Act { param($root) [pscustomobject]@{ Root = $root; Result = Invoke-Install $root -ExtraArgs '-Repair' } } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        $manifest = Import-Manifest $c.Root
        if (@($manifest.Artifacts).Count -ne 1 -or $manifest.Artifacts[0].Name -ne 'instructions' -or $manifest.McpInstalled) { throw 'Repair expanded retained scope.' }
        foreach ($name in @('copilot-instructions.md', 'agents', 'skills', 'mcp-config.json')) {
            if (Test-Path -LiteralPath (Join-Path $c.Root $name)) { throw "Repair recreated $name." }
        }
    }

Test-Case -Name 'Uninstall_Should_FailBeforeChangesWhenStateCannotBeWrittenAndRetrySafely' `
    -Arrange {
        $root = New-FixtureRoot
        Assert-InstallSuccess (Invoke-Install $root)
        [pscustomobject]@{ Root = $root; Before = Get-FixtureSnapshot $root }
    } `
    -Act {
        param($f)
        $lock = [System.IO.File]::Open((Get-ManifestPath $f.Root), 'Open', 'ReadWrite', 'Read')
        try { $failed = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
        finally { $lock.Dispose() }
        $afterFailure = Get-FixtureSnapshot $f.Root
        [pscustomobject]@{ Fixture = $f; Failed = $failed; AfterFailure = $afterFailure; Retry = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
    } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Failed
        if ($c.Failed.Output -match 'Uninstall complete' -or $c.AfterFailure -ne $c.Fixture.Before) { throw 'Locked-state uninstall mutated or claimed success.' }
        Assert-InstallSuccess $c.Retry
        if (Test-Path -LiteralPath (Get-ManifestPath $c.Fixture.Root)) { throw 'Retry did not finish cleanup.' }
    }

foreach ($selector in @('environment', 'explicit', 'fallback')) {
    Test-Case -Name "HomeSelection_Should_IsolateAllModesFor_$selector" `
        -Arrange {
            $profileRoot = New-FixtureRoot
            $alternate = New-FixtureRoot
            $explicitRoot = New-FixtureRoot
            $environment = @{ HOME = $profileRoot; USERPROFILE = $profileRoot; COPILOT_HOME = $alternate }
            $parameters = @{ TargetRoot = $explicitRoot; Environment = $environment }
            $expected = $explicitRoot
            if ($selector -ne 'explicit') {
                $parameters.UseDefaultTarget = $true
                $expected = $alternate
            }
            if ($selector -eq 'fallback') {
                $environment.COPILOT_HOME = $null
                $expected = Join-Path $profileRoot '.copilot'
            }
            [pscustomobject]@{
                Parameters = $parameters; Expected = $expected
                Others = @((Join-Path $profileRoot '.copilot'), $alternate, $explicitRoot) | Where-Object { $_ -ne $expected }
            }
        } `
        -Act {
            param($f)
            $parameters = $f.Parameters
            Assert-InstallSuccess (Invoke-Install @parameters)
            $manifest = Import-Manifest $f.Expected
            foreach ($mode in @('-Status', '-Repair')) {
                Assert-InstallSuccess (Invoke-Install @parameters -ExtraArgs $mode)
            }
            [pscustomobject]@{
                Fixture = $f; Manifest = $manifest
                Result = Invoke-Install @parameters -ExtraArgs '-Uninstall'
            }
        } `
        -Assert {
            param($c)
            Assert-InstallSuccess $c.Result
            if ($c.Manifest.TargetRoot -ne $c.Fixture.Expected) { throw 'The wrong home was selected.' }
            if (Test-Path -LiteralPath (Get-ManifestPath $c.Fixture.Expected)) { throw 'The selected home was not uninstalled.' }
            foreach ($other in $c.Fixture.Others) {
                foreach ($name in (@($script:CoreLinkNames) + '.np-copilot-installer')) {
                    if (Test-Path -LiteralPath (Join-Path $other $name)) { throw 'An unselected home was modified.' }
                }
            }
        }
}

Test-Case -Name 'Manifest_Should_UpgradeSupportedVersionOneWithoutLosingRestorePoint' `
    -Arrange {
        $root = New-FixtureRoot
        New-Item -ItemType Directory -Path (Join-Path $root 'instructions') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'instructions\original.txt') -Value 'v1 original'
        Assert-InstallSuccess (Invoke-Install $root)
        $manifest = Import-Manifest $root
        $manifest.SchemaVersion = 1
        $manifest.PSObject.Properties.Remove('RecoveryPaths')
        foreach ($artifact in $manifest.Artifacts) { $artifact.PSObject.Properties.Remove('BackupHistory') }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Get-ManifestPath $root)
        $root
    } `
    -Act {
        param($root)
        Assert-InstallSuccess (Invoke-Install $root)
        [pscustomobject]@{ Root = $root; Result = Invoke-Install $root -ExtraArgs '-Uninstall' }
    } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        if ((Get-Content -LiteralPath (Join-Path $c.Root 'instructions\original.txt') -Raw).Trim() -ne 'v1 original') { throw 'Version-one recovery point was lost.' }
    }

Test-Case -Name 'McpPreflight_Should_RejectHardLinkedConfigurationWithoutChangingAliases' `
    -Arrange {
        $root = New-FixtureRoot
        $foreign = New-FixtureRoot
        $path = Join-Path $foreign 'original.json'
        Set-Content -LiteralPath $path -Value '{"mcpServers":{}}' -NoNewline
        New-Item -ItemType HardLink -Path (Join-Path $root 'mcp-config.json') -Target $path | Out-Null
        [pscustomobject]@{ Root = $root; Foreign = $path; Hash = (Get-FileHash -LiteralPath $path).Hash }
    } `
    -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root -ExtraArgs '-Mcp' } } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Result
        if ((Get-FileHash -LiteralPath $c.Fixture.Foreign).Hash -ne $c.Fixture.Hash) { throw 'Hard-link alias was changed.' }
        if (Test-Path -LiteralPath (Get-ManifestPath $c.Fixture.Root)) { throw 'An aliased merge was recorded as successful.' }
    }

Test-Case -Name 'McpJson_Should_PreserveUserStringNumberArrayAndDeepObjectValues' `
    -Arrange {
        $root = New-FixtureRoot
        $path = Join-Path $root 'mcp-config.json'
        $deep = '"deep-value"'
        foreach ($level in 1..15) { $deep = '{"nested":' + $deep + '}' }
        $content = '{"metadata":{"date":"2026-01-02T03:04:05+09:00","number":123456789012345678901234567890.123456789,"array":[[],[null],false],"deep":' + $deep + '},"mcpServers":{}}'
        Set-Content -LiteralPath $path -Value $content -NoNewline
        [pscustomobject]@{ Root = $root; Path = $path; Content = $content }
    } `
    -Act {
        param($f)
        Assert-InstallSuccess (Invoke-Install $f.Root -ExtraArgs '-Mcp')
        $merged = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $f.Path -Raw))
        try {
            $metadata = $merged.RootElement.GetProperty('metadata')
            $date = $metadata.GetProperty('date').GetString()
            $number = $metadata.GetProperty('number').GetRawText()
            $array = $metadata.GetProperty('array')
            $arrayShape = @($array[0].GetArrayLength(), $array[1].GetArrayLength(), $array[1][0].ValueKind.ToString(), $array[2].GetBoolean())
            $deep = $metadata.GetProperty('deep')
            foreach ($level in 1..15) { $deep = $deep.GetProperty('nested') }
            $deepValue = $deep.GetString()
        }
        finally { $merged.Dispose() }
        [pscustomobject]@{
            Fixture = $f; Date = $date; Number = $number; Shape = $arrayShape; Deep = $deepValue
            Result = Invoke-Install $f.Root -ExtraArgs '-Uninstall'
        }
    } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        if ($c.Date -cne '2026-01-02T03:04:05+09:00' -or $c.Number -cne '123456789012345678901234567890.123456789' -or
            ($c.Shape -join ',') -cne '0,1,Null,False' -or $c.Deep -ne 'deep-value') { throw 'MCP merge transformed user-owned JSON values.' }
        if ((Get-Content -LiteralPath $c.Fixture.Path -Raw) -cne $c.Fixture.Content) { throw 'Uninstall did not restore the original bytes.' }
    }

foreach ($ambiguousJson in @('{"mcpServers":{},"McpServers":{}}', '{"mcpServers":{},"metadata":1,"metadata":2}')) {
    Test-Case -Name "McpJson_Should_RejectAmbiguousObjectKeys_$ambiguousJson" `
        -Arrange {
            $root = New-FixtureRoot
            Set-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Value $ambiguousJson -NoNewline
            [pscustomobject]@{ Root = $root; Before = Get-FixtureSnapshot $root }
        } `
        -Act { param($f) [pscustomobject]@{ Fixture = $f; Result = Invoke-Install $f.Root -ExtraArgs '-Mcp' } } `
        -Assert {
            param($c)
            Assert-InstallFailure $c.Result
            if ((Get-FixtureSnapshot $c.Fixture.Root) -ne $c.Fixture.Before) { throw 'Ambiguous JSON was rewritten.' }
        }
}

Test-Case -Name 'Review_Should_PreserveLiteralPSTypeNameAndLaterUserChanges' `
    -Arrange {
        $root = New-FixtureRoot
        $path = Join-Path $root 'mcp-config.json'
        Set-Content -LiteralPath $path -Value '{"metadata":{"PSTypeName":"User.Metadata","keep":"v"},"mcpServers":{}}' -NoNewline
        [pscustomobject]@{ Root = $root; Path = $path }
    } `
    -Act {
        param($f)
        Assert-InstallSuccess (Invoke-Install $f.Root -ExtraArgs '-Mcp')
        $merged = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $f.Path -Raw))
        try { $typeName = $merged.RootElement.GetProperty('metadata').GetProperty('PSTypeName').GetString() }
        finally { $merged.Dispose() }
        $edited = (Get-Content -LiteralPath $f.Path -Raw).Replace('"User.Metadata"', '"Changed.Metadata"')
        Set-Content -LiteralPath $f.Path -Value $edited -NoNewline
        [pscustomobject]@{ Fixture = $f; TypeName = $typeName; Result = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
    } `
    -Assert {
        param($c)
        Assert-InstallSuccess $c.Result
        if ($c.TypeName -ne 'User.Metadata') { throw 'PSTypeName was consumed as PowerShell metadata.' }
        $final = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $c.Fixture.Path -Raw))
        try {
            if ($final.RootElement.GetProperty('metadata').GetProperty('PSTypeName').GetString() -ne 'Changed.Metadata') {
                throw 'A literal user field edit was overwritten during uninstall.'
            }
        }
        finally { $final.Dispose() }
    }

Test-Case -Name 'Review_Should_PersistCompletedRestoresBeforeLaterArtifactFailure' `
    -Arrange {
        $root = New-FixtureRoot
        Set-Content -LiteralPath (Join-Path $root 'copilot-instructions.md') -Value 'first original' -NoNewline
        Set-Content -LiteralPath (Join-Path $root 'instructions') -Value 'second original' -NoNewline
        Assert-InstallSuccess (Invoke-Install $root)
        $second = (Import-Manifest $root).Artifacts | Where-Object Name -eq 'instructions'
        [pscustomobject]@{ Root = $root; SecondBackup = $second.BackupPath }
    } `
    -Act {
        param($f)
        $lock = [System.IO.File]::Open($f.SecondBackup, 'Open', 'Read', 'None')
        try { $failed = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
        finally { $lock.Dispose() }
        $pending = Import-Manifest $f.Root
        $status = Invoke-Install $f.Root -ExtraArgs '-Status'
        [pscustomobject]@{ Fixture = $f; Failed = $failed; Pending = $pending; Status = $status; Retry = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
    } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Failed
        Assert-InstallSuccess $c.Status
        Assert-InstallSuccess $c.Retry
        if ($c.Pending.Artifacts.Name -contains 'copilot-instructions.md') { throw 'Completed restore still references a consumed backup.' }
        if ((Get-Content -LiteralPath (Join-Path $c.Fixture.Root 'copilot-instructions.md') -Raw) -ne 'first original' -or
            (Get-Content -LiteralPath (Join-Path $c.Fixture.Root 'instructions') -Raw) -ne 'second original') { throw 'A late failure lost original content.' }
    }

foreach ($editDuringRecovery in @($false, $true)) {
    Test-Case -Name "Review_Should_ResumeRestoreAfterPublicationFailure_Edited_$editDuringRecovery" `
        -Arrange {
            $source = New-IsolatedSourceRoot
            $installer = Join-Path $source 'install.ps1'
            $root = New-FixtureRoot
            $target = Join-Path $root 'copilot-instructions.md'
            Set-Content -LiteralPath $target -Value 'recoverable original' -NoNewline
            Assert-InstallSuccess (Invoke-Install $root -InstallScriptPath $installer)
            $originalScript = Get-Content -LiteralPath $installer -Raw
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
            $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Complete-UninstallArtifact' }, $true)
            $call = 'Save-UninstallProgress -Manifest $Manifest -ManifestPath $ManifestPath'
            if (-not $function -or -not $function.Extent.Text.Contains($call)) { throw 'Completion publication fault boundary was not found.' }
            $faultedFunction = $function.Extent.Text.Replace($call, "throw 'injected completion publication failure'")
            $faultedScript = $originalScript.Substring(0, $function.Extent.StartOffset) + $faultedFunction + $originalScript.Substring($function.Extent.EndOffset)
            Set-Content -LiteralPath $installer -Value $faultedScript -NoNewline
            [pscustomobject]@{ Root = $root; Installer = $installer; OriginalScript = $originalScript; Target = $target; Edit = $editDuringRecovery }
        } `
        -Act {
            param($f)
            $failed = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Uninstall'
            Set-Content -LiteralPath $f.Installer -Value $f.OriginalScript -NoNewline
            $pending = Import-Manifest $f.Root
            $status = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Status'
            $repair = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Repair'
            $editedRetry = $null
            $editedBytes = $null
            if ($f.Edit) {
                Set-Content -LiteralPath $f.Target -Value 'user edited restored original' -NoNewline
                $editedRetry = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Uninstall'
                $editedBytes = Get-Content -LiteralPath $f.Target -Raw
                Set-Content -LiteralPath $f.Target -Value 'recoverable original' -NoNewline
            }
            [pscustomobject]@{
                Fixture = $f; Failed = $failed; Pending = $pending; Status = $status; Repair = $repair
                EditedRetry = $editedRetry; EditedBytes = $editedBytes
                Retry = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Uninstall'
            }
        } `
        -Assert {
            param($c)
            Assert-InstallFailure $c.Failed
            if ($c.Failed.Output -notmatch 'injected completion publication failure') { throw $c.Failed.Output }
            $pending = $c.Pending.Artifacts | Where-Object Name -eq 'copilot-instructions.md'
            if ($pending.UninstallState -ne 'PendingRestore' -or -not $pending.RestoreHash) { throw 'Restore intent was not durable.' }
            Assert-InstallSuccess $c.Status
            Assert-InstallFailure $c.Repair
            if ($c.Fixture.Edit) {
                Assert-InstallFailure $c.EditedRetry
                if ($c.EditedBytes -ne 'user edited restored original') { throw 'A changed restored target was overwritten.' }
            }
            Assert-InstallSuccess $c.Retry
            if ((Get-Content -LiteralPath $c.Fixture.Target -Raw) -ne 'recoverable original') { throw 'Retry did not preserve the restored original.' }
            if (Test-Path -LiteralPath (Get-ManifestPath $c.Fixture.Root)) { throw 'Recovery did not finish.' }
        }
}

Test-Case -Name 'Review_Should_RetainMcpRecoveryCopyWhenRollbackRestorationFails' `
    -Arrange {
        $source = New-IsolatedSourceRoot
        $installer = Join-Path $source 'install.ps1'
        $root = New-FixtureRoot
        $target = Join-Path $root 'mcp-config.json'
        Set-Content -LiteralPath $target -Value '{"mcpServers":{},"marker":"original"}' -NoNewline
        Assert-InstallSuccess (Invoke-Install $root -InstallScriptPath $installer -ExtraArgs '-Mcp')
        $beforeHash = (Get-FileHash -LiteralPath $target).Hash
        $sourceMcp = Join-Path $source 'mcp-config.json'
        $json = Get-Content -LiteralPath $sourceMcp -Raw | ConvertFrom-Json
        $name = @($json.mcpServers.PSObject.Properties.Name)[0]
        $json.mcpServers.$name | Add-Member -NotePropertyName revisionMarker -NotePropertyValue 'new revision'
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourceMcp
        $scriptText = Get-Content -LiteralPath $installer -Raw
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Undo-Transaction' }, $true)
        $call = 'Copy-Item -LiteralPath $entry.PreviousContentPath -Destination $entry.Path -Force'
        if (-not $function -or -not $function.Extent.Text.Contains($call)) { throw 'Rollback restoration fault boundary was not found.' }
        $faultedFunction = $function.Extent.Text.Replace($call, "throw 'injected rollback restoration failure'")
        $faultedScript = $scriptText.Substring(0, $function.Extent.StartOffset) + $faultedFunction + $scriptText.Substring($function.Extent.EndOffset)
        Set-Content -LiteralPath $installer -Value $faultedScript -NoNewline
        [pscustomobject]@{ Root = $root; Installer = $installer; Target = $target; BeforeHash = $beforeHash }
    } `
    -Act {
        param($f)
        $lock = [System.IO.File]::Open((Get-ManifestPath $f.Root), 'Open', 'ReadWrite', 'Read')
        try { $result = Invoke-Install $f.Root -InstallScriptPath $f.Installer -ExtraArgs '-Repair' }
        finally { $lock.Dispose() }
        [pscustomobject]@{ Fixture = $f; Result = $result }
    } `
    -Assert {
        param($c)
        Assert-InstallFailure $c.Result
        if ($c.Result.Output -notmatch 'injected rollback restoration failure' -or $c.Result.Output -notmatch 'recovery copy must be retained') { throw $c.Result.Output }
        $recoveryCopies = @(
            foreach ($run in Get-ChildItem -LiteralPath (Join-Path $c.Fixture.Root '.np-copilot-installer\backups') -Directory) {
                $path = Join-Path $run.FullName 'mcp-config.json'
                if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-FileHash -LiteralPath $path).Hash -eq $c.Fixture.BeforeHash) { $path }
            }
        )
        if ($recoveryCopies.Count -lt 1) { throw 'The failed rollback deleted its pre-run recovery copy.' }
        if ((Get-FileHash -LiteralPath $c.Fixture.Target).Hash -eq $c.Fixture.BeforeHash) { throw 'The injected rollback failure was not exercised.' }
    }

foreach ($matchingTransition in @($false, $true)) {
    Test-Case -Name "Review_Should_SeparateMcpLinkAndMergeRestorePoints_Matching_$matchingTransition" `
        -Arrange {
            $root = New-FixtureRoot
            $foreignRoot = New-FixtureRoot
            $foreign = Join-Path $foreignRoot 'original.json'
            $target = Join-Path $root 'mcp-config.json'
            Set-Content -LiteralPath $foreign -Value '{"mcpServers":{},"original":"foreign"}' -NoNewline
            New-Item -ItemType SymbolicLink -Path $target -Target $foreign | Out-Null
            Assert-InstallSuccess (Invoke-Install $root -ExtraArgs '-Mcp')
            $oldBackup = ((Import-Manifest $root).Artifacts | Where-Object Name -eq 'mcp-config.json').BackupPath
            (Get-Item -LiteralPath $target -Force).Delete()
            $replacement = if ($matchingTransition) { Get-Content -LiteralPath (Get-RepoSourcePath 'mcp-config.json') -Raw } else { '{"mcpServers":{},"replacement":"ordinary"}' }
            Set-Content -LiteralPath $target -Value $replacement -NoNewline
            [pscustomobject]@{ Root = $root; Target = $target; Foreign = $foreign; OldBackup = $oldBackup; Replacement = $replacement; ForeignHash = (Get-FileHash -LiteralPath $foreign).Hash }
        } `
        -Act {
            param($f)
            Assert-InstallSuccess (Invoke-Install $f.Root -ExtraArgs '-Repair')
            $artifact = (Import-Manifest $f.Root).Artifacts | Where-Object Name -eq 'mcp-config.json'
            $ordinaryBackup = -not (Get-Item -LiteralPath $artifact.BackupPath -Force).LinkType
            $status = Invoke-Install $f.Root -ExtraArgs '-Status'
            [pscustomobject]@{ Fixture = $f; Artifact = $artifact; OrdinaryBackup = $ordinaryBackup; Status = $status; Result = Invoke-Install $f.Root -ExtraArgs '-Uninstall' }
        } `
        -Assert {
            param($c)
            Assert-InstallSuccess $c.Status
            Assert-InstallSuccess $c.Result
            if (-not $c.OrdinaryBackup -or $c.Artifact.Kind -ne 'McpMerge' -or $c.Artifact.BackupHistory -notcontains $c.Fixture.OldBackup) {
                throw 'Link-to-merge transition produced invalid recovery ownership.'
            }
            if ((Get-Content -LiteralPath $c.Fixture.Target -Raw) -cne $c.Fixture.Replacement) { throw 'Latest ordinary file was not restored exactly.' }
            if (-not (Test-IsSymlinkTo $c.Fixture.OldBackup $c.Fixture.Foreign) -or
                (Get-FileHash -LiteralPath $c.Fixture.Foreign).Hash -ne $c.Fixture.ForeignHash) { throw 'Earlier foreign link was not retained unchanged.' }
        }
}
