#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'New-ConfigHookFixture.ps1')

$metadataCases = @(
    @{ Name = 'MissingDescription'; Replacement = ''; Pattern = 'has no description frontmatter value' },
    @{ Name = 'EmptyDescription'; Replacement = 'description:'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'WhitespaceDescription'; Replacement = 'description: "   "'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'BooleanDescription'; Replacement = 'description: true'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'NumericDescription'; Replacement = 'description: 12'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'NullDescription'; Replacement = 'description: null'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'SequenceDescription'; Replacement = 'description: [one, two]'; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'MappingDescription'; Replacement = "description:`n  nested: value"; Pattern = "frontmatter 'description' must be a nonempty string" },
    @{ Name = 'UnterminatedCollection'; Replacement = 'description: [broken'; Pattern = 'invalid repository YAML frontmatter.*unterminated flow sequence' },
    @{ Name = 'UnterminatedQuote'; Replacement = 'description: "broken'; Pattern = 'invalid repository YAML frontmatter.*malformed double-quoted scalar' },
    @{ Name = 'NestedFlowCollection'; Replacement = 'description: [[broken]]'; Pattern = 'invalid repository YAML frontmatter.*nested flow collections' },
    @{ Name = 'UnquotedMappingSyntax'; Replacement = 'description: invalid: mapping'; Pattern = 'invalid repository YAML frontmatter.*ambiguous plain scalar' },
    @{ Name = 'Anchor'; Replacement = 'description: &anchor value'; Pattern = 'invalid repository YAML frontmatter.*unsupported' },
    @{ Name = 'Alias'; Replacement = 'description: *anchor'; Pattern = 'invalid repository YAML frontmatter.*unsupported' },
    @{ Name = 'MalformedEntry'; Replacement = "description: valid`nthis is not a mapping entry"; Pattern = 'invalid repository YAML frontmatter.*mapping entry' },
    @{ Name = 'QuotedUnsupportedKey'; Replacement = "description: valid`n`"tags`": []"; Pattern = "uses unsupported agent frontmatter key 'tags'" },
    @{ Name = 'EscapedUnsupportedKey'; Replacement = 'description: valid' + "`n" + '"ta\u0067s": []'; Pattern = "uses unsupported agent frontmatter key 'tags'" },
    @{ Name = 'DuplicateQuotedKey'; Replacement = "description: valid`n'description': duplicate"; Pattern = "duplicate YAML key 'description'" },
    @{ Name = 'ScalarTools'; Replacement = "description: valid`ntools: read"; Pattern = "frontmatter 'tools' must be a nonempty string sequence" },
    @{ Name = 'BooleanTools'; Replacement = "description: valid`ntools: [read, true]"; Pattern = "frontmatter 'tools' must be a nonempty string sequence" },
    @{ Name = 'EmptyTools'; Replacement = "description: valid`ntools: []"; Pattern = "frontmatter 'tools' must be a nonempty string sequence" },
    @{ Name = 'TabIndent'; Replacement = "description: valid`ntools:`n`t- read"; Pattern = 'tabs.*unsupported YAML' },
    @{ Name = 'RawControl'; Replacement = "description: invalid$([char]1)text"; Pattern = 'control characters.*unsupported YAML' },
    @{ Name = 'FlowCommentHidesTerminator'; Replacement = "description: valid`ntools: [read, search # comment]"; Pattern = 'comments inside flow sequences are unsupported' },
    @{ Name = 'SingleQuotedDescription'; Replacement = "description: 'It''s a valid description.'"; Pass = $true },
    @{ Name = 'DoubleQuotedDescription'; Replacement = 'description: "Valid \u0064escription."'; Pass = $true },
    @{ Name = 'FoldedDescription'; Replacement = "description: >`n  Folded description`n  continues here."; Pass = $true },
    @{ Name = 'LiteralDescription'; Replacement = "description: |-`n  Literal description`n  continues here."; Pass = $true },
    @{ Name = 'QuotedToolSequence'; Replacement = "description: valid`ntools: [`"read`", 'search']"; Pass = $true },
    @{ Name = 'QuotedHashInFlow'; Replacement = "description: valid`ntools: [`"read#literal`", 'search']"; Pass = $true }
)
foreach ($case in $metadataCases) {
    Test-Case -Name "StrictFrontmatter_$($case.Name)" -Arrange {
        $root = New-BaselineFixture
        $path = Join-Path $root 'agents\sample-agent.md'
        $content = Get-Content -LiteralPath $path -Raw
        $needle = 'description: Fixture agent used for regression testing.'
        if (-not $content.Contains($needle)) { throw 'Description mutation is a no-op.' }
        [IO.File]::WriteAllText($path, $content.Replace($needle, $case.Replacement))
        $root
    } -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
        param($r)
        if ($case.Pass) {
            if ($r.ExitCode -ne 0) { throw "Positive YAML control failed: $($r.Output)" }
        }
        elseif ($r.ExitCode -ne 1 -or $r.Output -notmatch $case.Pattern) {
            throw "Expected nonzero '$($case.Pattern)': $($r.Output)"
        }
    }
}

Test-Case -Name 'Frontmatter_InvalidUtf8IsNotSilentlyReplaced' -Arrange {
    $root = New-BaselineFixture
    $path = Join-Path $root 'agents\sample-agent.md'
    $bytes = [Text.Encoding]::UTF8.GetBytes("---`nname: sample-agent`ndescription: ")
    $bytes += [byte[]]@(0xc3, 0x28)
    $bytes += [Text.Encoding]::UTF8.GetBytes("`nmodel: claude-sonnet-5`n---`n")
    [IO.File]::WriteAllBytes($path, $bytes)
    $root
} -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
    param($r)
    if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'cannot be read as definition text') { throw $r.Output }
}

Test-Case -Name 'Reviewer_InvalidToolsNeverReportsAPassingCapabilityBoundary' -Arrange {
    $root = New-BaselineFixture
    New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody -ExtraFrontmatterLines @('tools: read')
    $root
} -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
    param($r)
    if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'must declare a valid reviewer tools string sequence' -or
        $r.Output -match 'Code reviewer is restricted to read/search and workflows own report persistence') { throw $r.Output }
}

foreach ($kind in @('agent', 'skill')) {
    Test-Case -Name "RequiredDescription_$kind" -Arrange {
        $root = New-BaselineFixture
        if ($kind -eq 'agent') { New-AgentFile -Root $root -BaseName 'sample-agent' -OmitDescription }
        else { New-SkillFile -Root $root -DirName 'codebase-research' -OmitDescription }
        $root
    } -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
        param($r)
        if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'has no description frontmatter value') { throw $r.Output }
    }
}

$runtimeCases = @(
    @{ Name = 'DockerUntagged'; Kind = 'docker'; Reference = 'example/image'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerPortWithoutTag'; Kind = 'docker'; Reference = 'registry.example:5000/image'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerLatest'; Kind = 'docker'; Reference = 'example/image:latest'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerMixedLatest'; Kind = 'docker'; Reference = 'example/image:Latest'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerNext'; Kind = 'docker'; Reference = 'example/image:next'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerLatestish'; Kind = 'docker'; Reference = 'example/image:latestish'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerPartialVersion'; Kind = 'docker'; Reference = 'example/image:1.2'; Pattern = 'explicit three-part image version' },
    @{ Name = 'DockerBadDigest'; Kind = 'docker'; Reference = 'example/image@sha256:abcd'; Pattern = 'complete SHA-256 image digest' },
    @{ Name = 'DockerDigest'; Kind = 'docker'; Reference = "example/image@sha256:$('a' * 64)"; Pass = $true },
    @{ Name = 'DockerTaggedDigest'; Kind = 'docker'; Reference = "example/image:latest@sha256:$('b' * 64)"; Pass = $true },
    @{ Name = 'DockerRegistryVersion'; Kind = 'docker'; Reference = 'registry.example:5000/team/image:1.2.3'; Pass = $true },
    @{ Name = 'ComposeUntagged'; Kind = 'compose'; Reference = 'example/image'; Pattern = 'explicit three-part image version' },
    @{ Name = 'ComposeMoving'; Kind = 'compose'; Reference = 'example/image:stable'; Pattern = 'explicit three-part image version' },
    @{ Name = 'ComposeInterpolation'; Kind = 'compose'; Reference = '${IMAGE}'; Pattern = 'unsupported or malformed image reference' },
    @{ Name = 'ComposeCalendarVersion'; Kind = 'compose'; Reference = 'example/image:2026.8.22-9fea41204'; Pass = $true },
    @{ Name = 'ComposeDigest'; Kind = 'compose'; Reference = "example/image@sha256:$('c' * 64)"; Pass = $true },
    @{ Name = 'NpxUnversioned'; Kind = 'npx'; Reference = 'example'; Pattern = 'exact package version' },
    @{ Name = 'NpxNext'; Kind = 'npx'; Reference = 'example@next'; Pattern = 'exact package version' },
    @{ Name = 'NpxLatest'; Kind = 'npx'; Reference = 'example@latest'; Pattern = 'exact package version' },
    @{ Name = 'NpxLatestish'; Kind = 'npx'; Reference = 'example@latestish'; Pattern = 'exact package version' },
    @{ Name = 'NpxRange'; Kind = 'npx'; Reference = 'example@^1.2.3'; Pattern = 'exact package version' },
    @{ Name = 'NpxWildcard'; Kind = 'npx'; Reference = 'example@1.2.x'; Pattern = 'exact package version' },
    @{ Name = 'NpxVersion'; Kind = 'npx'; Reference = 'example@1.2.3'; Pass = $true },
    @{ Name = 'NpxScopedVersion'; Kind = 'npx'; Reference = '@example/package@1.2.3-rc.1'; Pass = $true },
    @{ Name = 'WaiverDoesNotCoverNext'; Kind = 'npx'; Reference = '@playwright/mcp@next'; Pattern = 'exact package version' }
)
foreach ($case in $runtimeCases) {
    Test-Case -Name "RuntimeReference_$($case.Name)" -Arrange {
        $root = New-BaselineFixture
        if ($case.Kind -eq 'compose') {
            [IO.File]::WriteAllText((Join-Path $root 'mcps\docker-compose.yml'), "services:`n  example:`n    `"image`": `"$($case.Reference)`"`n")
        }
        else {
            $arguments = if ($case.Kind -eq 'docker') { @('run', '-i', '--rm', '-e', 'NOTE=pkg@next', $case.Reference) } else { @('-y', $case.Reference) }
            $config = @{ mcpServers = @{ example = @{ type = 'local'; command = $case.Kind; args = $arguments } } }
            [IO.File]::WriteAllText((Join-Path $root 'mcp-config.json'), ($config | ConvertTo-Json -Depth 8))
        }
        $root
    } -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
        param($r)
        if ($case.Pass) {
            if ($r.ExitCode -ne 0) { throw "Positive runtime control failed: $($r.Output)" }
        }
        elseif ($r.ExitCode -ne 1 -or $r.Output -notmatch $case.Pattern) { throw "Expected nonzero '$($case.Pattern)': $($r.Output)" }
    }
}

Test-Case -Name 'RuntimeReference_IgnoresNonRuntimeNotes' -Arrange {
    $root = New-BaselineFixture
    $config = Get-Content -LiteralPath (Join-Path $root 'mcp-config.json') -Raw | ConvertFrom-Json -AsHashtable
    $config.note = 'pkg@next, pkg@latest and image:latest are documentation, not runtime inputs.'
    [IO.File]::WriteAllText((Join-Path $root 'mcp-config.json'), ($config | ConvertTo-Json -Depth 8))
    $root
} -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
    param($r)
    if ($r.ExitCode -ne 0) { throw $r.Output }
}

foreach ($content in @(
    '{"mcpServers":{"example":{"type":"local","command":"docker","args":["run",false]}}}',
    '{"mcpServers":{"example":{"type":"local","command":"docker","args":["run","--unknown","example/image:1.2.3"]}}}',
    '{"mcpServers":{"example":{"type":"local","command":"npx","args":["--package"]}}}',
    '{"mcpServers":{"example":{"type":"local","command":"custom-launcher","args":["example@1.2.3"]}}}'
)) {
    Test-Case -Name "RuntimeReference_RejectsUnsupportedShape_$content" -Arrange {
        $root = New-BaselineFixture
        [IO.File]::WriteAllText((Join-Path $root 'mcp-config.json'), $content)
        $root
    } -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
        param($r)
        if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'runtime validation|unsupported|without its required value') { throw $r.Output }
    }
}

foreach ($kind in @('ignored agent', 'hidden agent', 'ignored skill')) {
    Test-Case -Name "InputDomain_Includes_$kind" -Arrange {
        $root = New-BaselineFixture
        if ($kind -eq 'ignored skill') {
            New-SkillFile -Root $root -DirName 'plugin-skill' -OmitDescription
            [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "skills/plugin-skill/`n")
        }
        else {
            $name = if ($kind -eq 'hidden agent' -and -not $IsWindows) { '.plugin-agent' } else { 'plugin-agent' }
            New-AgentFile -Root $root -BaseName $name -OmitDescription
            $path = Join-Path $root "agents\$name.md"
            if ($kind -eq 'hidden agent' -and $IsWindows) { [IO.File]::SetAttributes($path, [IO.FileAttributes]::Hidden) }
            [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "agents/$name.md`n")
        }
        $root
    } -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
        param($r)
        if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'has no description frontmatter value') { throw "Installable definition was skipped: $($r.Output)" }
    }
}

foreach ($kind in @('agent directory', 'skill directory', 'ancestor')) {
    Test-Case -Name "InputDomain_RefusesLinked_$kind" -Arrange {
        $root = New-BaselineFixture
        $other = New-BaselineFixture
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        if ($kind -eq 'agent directory') {
            Remove-Item -LiteralPath (Join-Path $root 'agents') -Recurse -Force
            $null = New-Item -ItemType $linkType -Path (Join-Path $root 'agents') -Target (Join-Path $other 'agents')
        }
        elseif ($kind -eq 'skill directory') {
            $null = New-Item -ItemType $linkType -Path (Join-Path $root 'skills\private-linked') -Target $other
        }
        else {
            $alias = Join-Path $script:ConfigFixtureContexts[$root].Root 'linked-root'
            $null = New-Item -ItemType $linkType -Path $alias -Target $other
            $script:LinkedValidationRoot = Join-Path $alias 'skills'
        }
        $root
    } -Act {
        param($root)
        if ($kind -ne 'ancestor') { return Invoke-Validator -RepositoryRoot $root -SkipDockerCompose }
        Invoke-IsolatedProcess -Context $script:ConfigFixtureContexts[$root] -FilePath (Get-Command pwsh).Source `
            -WorkingDirectory $root -ArgumentList @('-NoProfile', '-File', $validatorPath, '-RepositoryRoot', $script:LinkedValidationRoot, '-SkipDockerCompose') -AllowFailure
    } -Assert {
        param($r)
        if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'Linked.*(contents were not followed|unsupported)') { throw $r.Output }
        if ($r.Output -match 'has valid agent identity metadata') { throw 'Linked contents were validated before containment failed.' }
    }
}

Test-Case -Name 'InputDomain_RejectsNestedAgentLayoutsWithoutTraversal' -Arrange {
    $root = New-BaselineFixture
    $nested = Join-Path $root 'agents\nested-plugin'
    $null = New-Item -ItemType Directory -Path $nested
    [IO.File]::WriteAllText((Join-Path $nested 'plugin.md'), 'Not a supported flat definition')
    $root
} -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
    param($r)
    if ($r.ExitCode -ne 1 -or $r.Output -notmatch 'Nested agent definition directories are unsupported; contents were not traversed') { throw $r.Output }
}

Test-Case -Name 'InputDomain_AcceptsValidIgnoredDefinitions' -Arrange {
    $root = New-BaselineFixture
    New-AgentFile -Root $root -BaseName 'plugin-agent'
    New-SkillFile -Root $root -DirName 'plugin-skill'
    [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "agents/plugin-agent.md`nskills/plugin-skill/`n")
    Add-Content -LiteralPath (Join-Path $root 'README.md') -Value "`nplugin-agent.md`nplugin-skill/"
    if ($IsWindows) { [IO.File]::SetAttributes((Join-Path $root 'agents\plugin-agent.md'), [IO.FileAttributes]::Hidden) }
    $root
} -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } -Assert {
    param($r)
    if ($r.ExitCode -ne 0 -or $r.Output -notmatch 'plugin-agent.md has valid agent identity metadata' -or
        $r.Output -notmatch 'plugin-skill.*has valid skill identity metadata') { throw $r.Output }
}

$hookCases = @(
    @{ Name = 'Empty'; Pass = $true; Skip = $true },
    @{ Name = 'Unrelated'; Pass = $true; Skip = $true },
    @{ Name = 'ValidRelevant'; Pass = $true },
    @{ Name = 'UnstagedInvalid'; Pass = $true },
    @{ Name = 'StagedInvalid'; Pattern = 'outside the repository model policy' },
    @{ Name = 'DeleteReviewer'; Pattern = 'code-reviewer.md is missing' },
    @{ Name = 'RenameReviewerOut'; Pattern = 'code-reviewer.md is missing' },
    @{ Name = 'ReviewerTypeChange'; Pattern = 'Unsupported symbolic-link input' },
    @{ Name = 'ReviewerDirectoryCollision'; Pattern = 'Agent definition is a directory' },
    @{ Name = 'ExportIgnoreInvalidAgent'; Pattern = 'outside the repository model policy' },
    @{ Name = 'MissingValidator'; Pattern = 'Declared required validation input.*missing' },
    @{ Name = 'SnapshotValidatorOnly'; Pattern = 'failed with exit 19' },
    @{ Name = 'WritingValidator'; Pattern = "README.md.*changed bytes" },
    @{ Name = 'CorruptIndex'; Pattern = 'failed with exit.*index' },
    @{ Name = 'IndexDirectory'; Pattern = 'candidate index is not a regular file' },
    @{ Name = 'DiscoveryFailure'; Pattern = 'failed with exit.*not a git repository' }
)
foreach ($case in $hookCases) {
    Test-Case -Name "ConfigHook_$($case.Name)" -Arrange {
        $root = New-ConfigHookFixture
        switch ($case.Name) {
            'Unrelated' { Set-RepoFile $root 'unrelated.txt' 'unrelated'; $null = Invoke-Git $root @('add', '--', 'unrelated.txt') }
            'ValidRelevant' { Add-Content -LiteralPath (Join-Path $root 'README.md') -Value "`nRelevant documentation"; $null = Invoke-Git $root @('add', '--', 'README.md') }
            'UnstagedInvalid' {
                Add-Content -LiteralPath (Join-Path $root 'README.md') -Value "`nRelevant documentation"
                $null = Invoke-Git $root @('add', '--', 'README.md')
                New-AgentFile -Root $root -BaseName 'sample-agent' -Model 'invalid'
            }
            'StagedInvalid' {
                New-AgentFile -Root $root -BaseName 'sample-agent' -Model 'invalid'
                $null = Invoke-Git $root @('add', '--', 'agents')
                New-AgentFile -Root $root -BaseName 'sample-agent'
            }
            'DeleteReviewer' { $null = Invoke-Git $root @('rm', '-q', '--', 'agents/code-reviewer.md') }
            'RenameReviewerOut' { $null = Invoke-Git $root @('mv', '--', 'agents/code-reviewer.md', 'retired-reviewer.md') }
            'ReviewerTypeChange' { $null = Add-FixtureIndexBlob $root 'agents/code-reviewer.md' ([Text.Encoding]::UTF8.GetBytes('../outside')) -Mode '120000' }
            'ReviewerDirectoryCollision' {
                $null = Invoke-Git $root @('rm', '-q', '--', 'agents/code-reviewer.md')
                Set-RepoFile $root 'agents\code-reviewer.md\unexpected.txt' 'wrong type'
                $null = Invoke-Git $root @('add', '--', 'agents')
            }
            'ExportIgnoreInvalidAgent' {
                New-AgentFile -Root $root -BaseName 'invalid-agent' -Model 'invalid'
                Add-Content -LiteralPath (Join-Path $root 'README.md') -Value "`ninvalid-agent.md"
                Set-RepoFile $root '.gitattributes' "agents/invalid-agent.md export-ignore`n"
                $null = Invoke-Git $root @('add', '.')
            }
            'MissingValidator' { $null = Invoke-Git $root @('rm', '-q', '--', 'scripts/Validate-Config.ps1') }
            'SnapshotValidatorOnly' {
                $path = Join-Path $root 'scripts\Validate-Config.ps1'
                $original = [IO.File]::ReadAllBytes($path)
                [IO.File]::WriteAllText($path, 'param([string]$RepositoryRoot); exit 19')
                $null = Invoke-Git $root @('add', '--', 'scripts/Validate-Config.ps1')
                [IO.File]::WriteAllBytes($path, $original)
            }
            'WritingValidator' {
                Set-RepoFile $root 'scripts\Validate-Config.ps1' 'param([string]$RepositoryRoot); [IO.File]::WriteAllText((Join-Path $RepositoryRoot "README.md"), "mutated"); exit 0'
                $null = Invoke-Git $root @('add', '--', 'scripts/Validate-Config.ps1')
            }
            'CorruptIndex' { Set-RepoFile $root 'bad.index' 'not an index' }
            'IndexDirectory' { $null = New-Item -ItemType Directory -Path (Join-Path $root 'bad.index') }
            'DiscoveryFailure' { Remove-Item -LiteralPath (Join-Path $root '.git') -Recurse -Force }
        }
        $root
    } -Act {
        param($root)
        $environment = @{}
        if ($case.Name -in @('CorruptIndex', 'IndexDirectory')) { $environment.GIT_INDEX_FILE = Join-Path $root 'bad.index' }
        Invoke-ConfigHookFixture -Root $root -Environment $environment
    } -Assert {
        param($r)
        if ($case.Pass) {
            if ($r.ExitCode -ne 0) { throw $r.Output }
            if ($case.Skip -and $r.Output -match 'Validating staged Copilot configuration') { throw 'Unrelated/empty candidate did not skip validation.' }
            if (-not $case.Skip -and $r.Output -notmatch 'All \d+ configuration checks passed') { throw 'Relevant candidate skipped validation.' }
        }
        elseif ($r.ExitCode -ne 1 -or $r.Output -notmatch $case.Pattern) { throw "Expected nonzero '$($case.Pattern)': $($r.Output)" }
    }
}

foreach ($preview in @($true, $false)) {
    Test-Case -Name "HookSetup_PreservesIndex_Preview_$preview" -Arrange { New-ConfigHookFixture } -Act {
        param($root)
        $indexPath = Join-Path $root '.git\index'
        $configPath = Join-Path $root '.git\config'
        $beforeIndex = (Get-FileHash -LiteralPath $indexPath).Hash
        $beforeConfig = (Get-FileHash -LiteralPath $configPath).Hash
        $arguments = @('-NoProfile', '-File', (Join-Path $root 'scripts\Enable-ConfigGitHook.ps1'), '-RepositoryRoot', $root)
        if ($preview) { $arguments += '-WhatIf' }
        $result = Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$root] -FilePath (Get-Command pwsh).Source `
            -WorkingDirectory $root -ArgumentList $arguments
        if ((Get-FileHash -LiteralPath $indexPath).Hash -cne $beforeIndex) { throw 'Hook setup changed the fixture index.' }
        if ($preview) {
            if ((Get-FileHash -LiteralPath $configPath).Hash -cne $beforeConfig) { throw 'WhatIf changed Git config.' }
        }
        else {
            if ((Invoke-Git $root @('config', '--local', '--get', 'core.hooksPath')).Trim() -cne '.githooks') { throw 'Local hook setup did not persist.' }
            if (-not $IsWindows -and ([int][IO.File]::GetUnixFileMode((Join-Path $root '.githooks\pre-commit')) -band 64) -eq 0) { throw 'POSIX hook is not executable.' }
        }
        $result
    } -Assert { param($r) if ($r.ExitCode -ne 0) { throw $r.Output } }
}

Test-Case -Name 'EnabledHook_RealGitDispatchRejectsRequiredDeletionInFixture' -Arrange { New-ConfigHookFixture } -Act {
    param($root)
    $null = Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$root] -FilePath (Get-Command pwsh).Source `
        -WorkingDirectory $root -ArgumentList @('-NoProfile', '-File', (Join-Path $root 'scripts\Enable-ConfigGitHook.ps1'), '-RepositoryRoot', $root)
    $head = (Invoke-Git $root @('rev-parse', 'HEAD')).Trim()
    $null = Invoke-Git $root @('rm', '-q', '--', 'agents/code-reviewer.md')
    $result = Invoke-FixtureGit $root @('-c', 'core.hooksPath=.githooks', 'commit', '-m', 'must be rejected') -AllowFailure
    if ((Invoke-Git $root @('rev-parse', 'HEAD')).Trim() -cne $head) { throw 'The invalid fixture commit was created.' }
    $result
} -Assert {
    param($r)
    if ($r.ExitCode -eq 0 -or $r.Output -notmatch 'code-reviewer.md is missing') { throw "Real Git did not dispatch and reject via the enabled hook: $($r.Output)" }
}
