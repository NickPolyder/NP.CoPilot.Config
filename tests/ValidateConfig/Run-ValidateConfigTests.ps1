#Requires -Version 7.0
<#
.SYNOPSIS
    Deterministic, dependency-free regression suite for scripts\Validate-Config.ps1.
.DESCRIPTION
    Invokes the validator out-of-process against disposable fixtures under
    $env:TEMP. Never touches this repo's real agents/skills directories or
    ~/.copilot. No Pester, no third-party dependency.
.EXAMPLE
    pwsh -NoProfile -File .\tests\ValidateConfig\Run-ValidateConfigTests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:TestsPassed = 0
$script:TestsFailed = 0

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$validatorPath = Join-Path $repoRoot 'scripts\Validate-Config.ps1'

. (Join-Path $PSScriptRoot 'New-ValidateConfigFixture.ps1')

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

function Invoke-Validator {
    <#
    .SYNOPSIS
        Runs Validate-Config.ps1 out-of-process. Returns exit code + stdout.
    #>
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$SkipDockerCompose,
        [switch]$HideDocker
    )

    $extraArgs = @()
    if ($SkipDockerCompose) { $extraArgs += '-SkipDockerCompose' }

    if ($HideDocker) {
        # Isolate the docker-absent branch deterministically: scrub PATH only
        # for this child process, never for the test host or other tests.
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = (Get-Command pwsh).Source
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($validatorPath)
        $psi.ArgumentList.Add('-RepositoryRoot')
        $psi.ArgumentList.Add($RepositoryRoot)
        foreach ($a in $extraArgs) { $psi.ArgumentList.Add($a) }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.EnvironmentVariables['PATH'] = ''
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $stdout + $stderr }
    }

    $allArgs = @('-NoProfile', '-File', $validatorPath, '-RepositoryRoot', $RepositoryRoot) + $extraArgs
    $output = & pwsh @allArgs 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Test-Case {
    <#
    .SYNOPSIS
        Runs one AAA-structured test case with automatic fixture cleanup.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Arrange,   # returns fixture root path (or $null)
        [Parameter(Mandatory)][scriptblock]$Act,       # ($arranged) -> Invoke-Validator result
        [Parameter(Mandatory)][scriptblock]$Assert     # ($result) -> throws on failure
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
        if ($arranged -and (Test-Path -LiteralPath $arranged -PathType Container)) {
            Remove-FixtureRoot -Path $arranged
        }
    }
}

Write-Host ''
Write-Host '🔍 Running Validate-Config.ps1 regression suite...' -ForegroundColor Cyan
Write-Host ''

# Sentinel used by the hermeticity guard at the end of the suite: fixture
# names that must never legitimately exist in the active ~/.copilot tree.
$copilotAgentsDir = Join-Path $HOME '.copilot\agents'
$sentinelAgentPath = Join-Path $copilotAgentsDir 'sample-agent.md'

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_ExitZero_When_FixtureIsFullyValid' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
        if ($r.Output -notmatch '✅ All \d+ configuration checks passed\.') {
            throw "expected the aggregate success summary line. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Corrected boundary behavior: exactly one agent file
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_NotCrash_When_ExactlyOneAgentFileExists' `
    -Arrange {
        $root = New-BaselineFixture
        Remove-Item -LiteralPath (Join-Path $root 'agents\sample-agent.md')
        Remove-Item -LiteralPath (Join-Path $root 'agents\sample-agent-two.md')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -match 'Cannot bind argument') {
            throw "the single-element array-unwrap defect appears to have regressed. Output: $($r.Output)"
        }
        if ($r.Output -notmatch 'Agent and skill backticked references resolve') {
            throw "expected reference-integrity to pass cleanly with exactly one agent. Output: $($r.Output)"
        }
        if ($r.ExitCode -ne 0) { throw "expected exit 0 for an otherwise-valid single-agent fixture. Output: $($r.Output)" }
    }

# ---------------------------------------------------------------------------
# Boundary behavior: zero skill directories.
#
# Final state of the empty-fixture contract, verified directly against the
# script after all four AllowEmptyCollection fixes landed:
#   1. Test-ReferenceIntegrity's -DefinitionPaths, -KnownAgents, -KnownSkills
#   2. Test-Orchestration's -KnownSkills
#   3. Test-ReadmeInventory's -AgentNames, -SkillNames
# A collection/HashSet/array audit of the remaining mandatory collection
# parameters (Test-FrontmatterKeys' -AllowedKeys, Test-MutableRuntimeVersions'
# -Paths) confirmed those are only ever invoked with fixed, non-empty literal
# arrays in the script body, so they are not at risk of this defect class.
#
# With zero skill directories, the run no longer crashes anywhere. It
# produces an entirely ordinary validation result:
#   - Test-ReferenceIntegrity passes cleanly (no skills to conflict with).
#   - Test-Orchestration reports a normal Add-Failure finding for every
#     hardcoded orchestration node that isn't present as a known skill.
#   - Test-ReadmeInventory passes: with an empty -SkillNames array its
#     foreach loop simply performs zero skill-name checks (agent checks
#     still run normally), so it does not fail vacuously.
#   - The run still exits non-zero overall, solely because of the expected
#     orchestration and review-invariant findings, not any crash.
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_ReportOrdinaryFindings_NotCrash_When_NoSkillDirectoriesExist' `
    -Arrange {
        $root = New-BaselineFixture
        Remove-Item -LiteralPath (Join-Path $root 'skills') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $root 'skills') | Out-Null
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -match 'Cannot bind argument') {
            throw "expected no parameter-binding crash anywhere in the pipeline for zero skill directories (all AllowEmptyCollection fixes should hold end-to-end). Output: $($r.Output)"
        }
        if ($r.Output -notmatch "Agent and skill backticked references resolve") {
            throw "expected Test-ReferenceIntegrity to pass cleanly with zero skills. Output: $($r.Output)"
        }
        foreach ($expectedFinding in @(
                "Orchestration entry skill 'prd-workflow' does not exist.",
                "Orchestration entry skill 'dependency-audit' does not exist.",
                "Orchestration entry skill 'test-gap-analysis' does not exist."
            )) {
            if ($r.Output -notmatch [regex]::Escape($expectedFinding)) {
                throw "expected Test-Orchestration to report a normal missing-skill finding: '$expectedFinding'. Output: $($r.Output)"
            }
        }
        if ($r.Output -notmatch [regex]::Escape('README inventory includes every tracked agent and skill.')) {
            throw "expected Test-ReadmeInventory to pass (vacuously, for the empty skill set) rather than crash or fail. Output: $($r.Output)"
        }
        if ($r.ExitCode -eq 0) {
            throw "expected a non-zero exit due to the expected orchestration/review-invariant findings, even though no crash occurs. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Frontmatter failures
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_Fail_When_AgentFrontmatterHasUnsupportedKey' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -ExtraFrontmatterLines @('tags:')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "uses unsupported agent frontmatter key 'tags'") {
            throw "expected unsupported-key failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_NameKeyIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -OmitName
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'has no name frontmatter value') {
            throw "expected missing-name failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_NameDoesNotMatchFileBaseName' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -Name 'wrong-name'
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "declares name 'wrong-name' but its expected name is 'sample-agent'") {
            throw "expected name-mismatch failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_AgentModelIsUnsupported' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -Model 'gpt-3.5-turbo'
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "uses unsupported model 'gpt-3.5-turbo'") {
            throw "expected unsupported-model failure. Output: $($r.Output)"
        }
    }

foreach ($supportedModel in @('claude-opus-4.8', 'claude-sonnet-5', 'gpt-5.5')) {
    Test-Case -Name "Validator_Should_Pass_When_AgentModelIs_$supportedModel" `
        -Arrange {
            $root = New-BaselineFixture
            New-AgentFile -Root $root -BaseName 'sample-agent' -Model $supportedModel
            $root
        } `
        -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
        -Assert {
            param($r)
            if ($r.Output -match 'uses unsupported model') {
                throw "did not expect an unsupported-model failure for '$supportedModel'. Output: $($r.Output)"
            }
        }
}

# ---------------------------------------------------------------------------
# Unknown routing reference
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_Fail_When_ReferenceIsToAnUnknownSkillOrAgent' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -Body 'Consult `ghost-skill` before proceeding.'
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "references unknown agent or skill 'ghost-skill'") {
            throw "expected unknown-reference failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Pass_When_ReferenceUsesRouteToPhrasingAndIsKnown' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -Body 'Route to `sample-agent-two` for follow-up.'
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -match 'references unknown agent or skill') {
            throw "did not expect an unknown-reference failure. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Missing orchestration node
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_Fail_When_OrchestrationChildSkillIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        Remove-Item -LiteralPath (Join-Path $root 'skills\dependency-audit-report') -Recurse -Force
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "Orchestration child skill 'dependency-audit-report' does not exist") {
            throw "expected missing-child-skill failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_OrchestrationParentSkillIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        Remove-Item -LiteralPath (Join-Path $root 'skills\test-gap-analysis') -Recurse -Force
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "Orchestration entry skill 'test-gap-analysis' does not exist") {
            throw "expected missing-parent-skill failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Pass_OrchestrationCheck_When_AllHardcodedNodesExist' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'Declared skill orchestration graph is valid') {
            throw "expected orchestration pass. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# README drift
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_Fail_When_ReadmeIsMissingAnAgent' `
    -Arrange {
        $root = New-BaselineFixture
        (Get-Content -Path (Join-Path $root 'README.md') -Raw) -replace 'sample-agent\.md', '' |
            Set-Content -Path (Join-Path $root 'README.md') -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "does not inventory agent 'sample-agent'") {
            throw "expected README agent-inventory failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReadmeIsMissingASkill' `
    -Arrange {
        $root = New-BaselineFixture
        (Get-Content -Path (Join-Path $root 'README.md') -Raw) -replace 'git-commit-review/', '' |
            Set-Content -Path (Join-Path $root 'README.md') -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch "does not inventory skill 'git-commit-review'") {
            throw "expected README skill-inventory failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Pass_ReadmeInventory_When_AllEntriesPresent' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'README inventory includes every tracked agent and skill') {
            throw "expected README inventory pass. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Malformed JSON
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_Fail_When_McpConfigJsonIsMalformed' `
    -Arrange {
        $root = New-BaselineFixture
        Set-Content -Path (Join-Path $root 'mcp-config.json') -Value '{"mcpServers": {,}}' -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'is not valid JSON') {
            throw "expected invalid-JSON failure. Output: $($r.Output)"
        }
    }

# Verified against the current script: Test-Json now checks
# [string]::IsNullOrWhiteSpace($content) explicitly before ever calling
# ConvertFrom-Json, and reports a normal Add-Failure finding for an empty
# (or whitespace-only) file instead of silently passing it.
Test-Case -Name 'Validator_Should_Fail_When_McpConfigJsonIsEmpty' `
    -Arrange {
        $root = New-BaselineFixture
        Set-Content -Path (Join-Path $root 'mcp-config.json') -Value '' -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'is empty and does not contain JSON') {
            throw "expected the empty-file JSON check to report a normal failure finding. Output: $($r.Output)"
        }
        if ($r.ExitCode -ne 1) { throw "expected exit 1 (a finding, not a crash). Output: $($r.Output)" }
    }

Test-Case -Name 'Validator_Should_Fail_When_McpConfigJsonIsWhitespaceOnly' `
    -Arrange {
        $root = New-BaselineFixture
        Set-Content -Path (Join-Path $root 'mcp-config.json') -Value "   `n`t  " -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'is empty and does not contain JSON') {
            throw "expected the whitespace-only JSON check to report a normal failure finding. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Pass_When_McpConfigJsonIsWellFormed' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'contains valid JSON') {
            throw "expected valid-JSON pass. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Mutable runtime versions - now case-insensitive end to end (corrected)
# ---------------------------------------------------------------------------

$mutableVersionCases = @(
    @{ Name = 'AtLatest_Lowercase'; Text = '"pkg@latest"'; Expect = $true }
    @{ Name = 'ColonLatest_Lowercase'; Text = 'image: x:latest'; Expect = $true }
    @{ Name = 'ColonLatest_MixedCase'; Text = 'image: x:Latest'; Expect = $true }
    @{ Name = 'ColonLatest_AllCaps'; Text = 'image: x:LATEST'; Expect = $true }
    @{ Name = 'AtLatest_Capitalized'; Text = '"pkg@Latest"'; Expect = $true }
    @{ Name = 'AtLatest_AllCaps'; Text = '"pkg@LATEST"'; Expect = $true }
    @{ Name = 'ColonLatestly_LongerIdentifier'; Text = 'image: x:latestly'; Expect = $false }
    @{ Name = 'AtLatestish_LongerIdentifier'; Text = '"pkg@latestish"'; Expect = $false }
)

foreach ($case in $mutableVersionCases) {
    Test-Case -Name "Validator_MutableVersionCheck_$($case.Name)" `
        -Arrange {
            $root = New-BaselineFixture
            Set-Content -Path (Join-Path $root 'mcp-config.json') -Value ('{"note": "' + $case.Text + '"}') -Encoding utf8 -NoNewline
            $root
        } `
        -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
        -Assert {
            param($r)
            $flagged = $r.Output -match 'contains a mutable runtime version'
            if ($flagged -ne $case.Expect) {
                throw "expected mutable-version flag=$($case.Expect) for '$($case.Text)', got $flagged. Output: $($r.Output)"
            }
        }
}

Test-Case -Name 'Validator_Should_Pass_MutableVersionCheck_When_AllVersionsArePinned' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'Runtime MCP definitions use explicit versions') {
            throw "expected mutable-version pass. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_WarnButPass_ForUserApprovedPlaywrightLatest' `
    -Arrange {
        $root = New-BaselineFixture
        Set-Content -Path (Join-Path $root 'mcp-config.json') -Value '{"mcpServers":{"playwright":{"args":["@playwright/mcp@latest"]}}}' -Encoding utf8 -NoNewline
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.ExitCode -ne 0 -or $r.Output -notmatch 'user-approved waiver') {
            throw "expected approved Playwright latest warning with successful exit. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Docker Compose branch
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_SkipDockerCompose_When_SwitchIsSupplied' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'Skipped Docker Compose validation by request') {
            throw "expected explicit-skip warning. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_WarnDockerUnavailable_When_DockerCommandCannotBeResolved' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -HideDocker } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'Docker is unavailable; skipped Docker Compose validation') {
            throw "expected docker-unavailable warning. Output: $($r.Output)"
        }
    }

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Test-Case -Name 'Validator_Should_PassDockerCompose_When_ComposeFileIsValid' `
        -Arrange { New-BaselineFixture } `
        -Act { param($root) Invoke-Validator -RepositoryRoot $root } `
        -Assert {
            param($r)
            if ($r.Output -notmatch 'passes docker compose config validation') {
                throw "expected docker compose pass. Output: $($r.Output)"
            }
        }

    Test-Case -Name 'Validator_Should_FailDockerCompose_When_ComposeFileIsInvalid' `
        -Arrange {
            $root = New-BaselineFixture
            Set-Content -Path (Join-Path $root 'mcps\docker-compose.yml') -Value 'not: [valid, compose' -Encoding utf8 -NoNewline
            $root
        } `
        -Act { param($root) Invoke-Validator -RepositoryRoot $root } `
        -Assert {
            param($r)
            if ($r.Output -notmatch 'failed docker compose config validation') {
                throw "expected docker compose failure. Output: $($r.Output)"
            }
        }
}
else {
    Write-Host '  ⚠️  Docker not found on this machine; skipping docker-compose-available branch tests (not counted as pass or fail).' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Missing invariant file - corrected: normal finding, not a crash
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_ReportFinding_When_GitCommitReviewSkillFileIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        Remove-Item -LiteralPath (Join-Path $root 'skills\git-commit-review\SKILL.md')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -match 'Cannot find path') {
            throw "the unguarded Get-Content crash appears to have regressed. Output: $($r.Output)"
        }
        if ($r.Output -notmatch [regex]::Escape('skills/git-commit-review/SKILL.md is missing; cannot verify review invariant: Git commit review materializes an index-only snapshot.')) {
            throw "expected a normal missing-file finding for the snapshot invariant. Output: $($r.Output)"
        }
        if ($r.Output -notmatch [regex]::Escape('skills/git-commit-review/SKILL.md is missing; cannot verify review invariant: Git commit review blocks reviewers after snapshot failure.')) {
            throw "expected a normal missing-file finding for the stop-before-reviewer invariant. Output: $($r.Output)"
        }
        if ($r.ExitCode -ne 1) { throw "expected exit 1 (findings reported, not a crash). Output: $($r.Output)" }
    }

Test-Case -Name 'Validator_Should_Fail_When_SnapshotMaterializationPatternIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        New-SkillFile -Root $root -DirName 'git-commit-review' -Body "# git-commit-review`n`nNo snapshot instructions here."
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'violates review invariant: Git commit review materializes an index-only snapshot') {
            throw "expected snapshot-invariant failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ExplicitInvocationPatternIsMissing' `
    -Arrange {
        $root = New-BaselineFixture
        New-SkillFile -Root $root -DirName 'full-code-review' -Body "# full-code-review`n`nRuns automatically during any review."
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch 'violates review invariant: Full review requires explicit user invocation') {
            throw "expected explicit-invocation invariant failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Pass_AllThreeReviewInvariants_When_PatternsArePresent' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        foreach ($msg in @(
                'Git commit review materializes an index-only snapshot',
                'Git commit review blocks reviewers after snapshot failure',
                'Full review requires explicit user invocation'
            )) {
            if ($r.Output -notmatch [regex]::Escape($msg)) {
                throw "expected review-invariant pass message '$msg'. Output: $($r.Output)"
            }
        }
    }

# ---------------------------------------------------------------------------
# Reviewer capability boundary
# ---------------------------------------------------------------------------

$compliantReviewerBody = @'
# Code Reviewer Fixture

## Rules

- Do not create reports, directories, or any other artifacts.
'@

$reviewerPersistenceViolationBody = @'
# Code Reviewer Fixture

## Rules

- Do not create reports, directories, or any other artifacts.

## Bad Habit

After completing every review, write the report to disk for future reference.
'@

Test-Case -Name 'Validator_Should_Pass_ReviewerCapabilityBoundary_When_ToolsAreExactlyReadAndSearch' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape('Code reviewer is restricted to read/search and workflows own report persistence.')) {
            throw "expected reviewer-capability-boundary pass message. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReviewerToolsListIsAbsent' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape('agents/code-reviewer.md is missing its reviewer tools list.')) {
            throw "expected missing-tools-list failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReviewerIsMissingRequiredTool' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
            -ExtraFrontmatterLines @('tools:', '  - read')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape("agents/code-reviewer.md is missing required reviewer tool 'search'.")) {
            throw "expected missing-required-tool failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReviewerDeclaresExtraTool' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
            -ExtraFrontmatterLines @('tools:', '  - read', '  - search', '  - write')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape("agents/code-reviewer.md declares unauthorized reviewer tool 'write'.")) {
            throw "expected unauthorized-tool failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReviewerToolNameIsCaseMutated' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
            -ExtraFrontmatterLines @('tools:', '  - Read', '  - search')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape("agents/code-reviewer.md declares unauthorized reviewer tool 'Read'.")) {
            throw "expected case-sensitive unauthorized-tool failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_ReviewerToolsHaveDuplicateEntryMaskingMissingTool' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
            -ExtraFrontmatterLines @('tools:', '  - read', '  - read')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape("agents/code-reviewer.md is missing required reviewer tool 'search'.")) {
            throw "expected duplicate-entry-masks-missing-tool failure. Output: $($r.Output)"
        }
    }

$reviewerToolListForms = @(
    @{ Name = 'BlockListForm'; ExtraFrontmatterLines = @('tools:', '  - read', '  - search') }
    @{ Name = 'InlineListForm'; ExtraFrontmatterLines = @('tools: [read, search]') }
)
foreach ($form in $reviewerToolListForms) {
    Test-Case -Name "Validator_Should_Pass_ReviewerCapabilityBoundary_When_ToolsUse_$($form.Name)" `
        -Arrange {
            $root = New-BaselineFixture
            New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
                -ExtraFrontmatterLines $form.ExtraFrontmatterLines
            $root
        } `
        -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
        -Assert {
            param($r)
            if ($r.Output -notmatch [regex]::Escape('Code reviewer is restricted to read/search and workflows own report persistence.')) {
                throw "expected reviewer-capability-boundary pass for $($form.Name). Output: $($r.Output)"
            }
        }
}

Test-Case -Name 'Validator_Should_Fail_When_ReviewerClaimsReportPersistence' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $reviewerPersistenceViolationBody `
            -ExtraFrontmatterLines @('tools:', '  - read', '  - search')
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape('agents/code-reviewer.md must not claim review-report persistence.')) {
            throw "expected report-persistence-violation failure. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_GitCommitReviewSkillOmitsWorkflowOwnershipClaim' `
    -Arrange {
        $root = New-BaselineFixture
        New-SkillFile -Root $root -DirName 'git-commit-review' -Body @'
# git-commit-review

Uses git write-tree to build a tree object, then git archive --format=tar
to materialize an index-only snapshot for review.

If the snapshot cannot be materialized, stop before launching any reviewer.
'@
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape('skills/git-commit-review/SKILL.md must explicitly claim workflow-owned report persistence.')) {
            throw "expected missing-ownership-claim failure for git-commit-review. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_Fail_When_FullCodeReviewSkillOmitsWorkflowOwnershipClaim' `
    -Arrange {
        $root = New-BaselineFixture
        New-SkillFile -Root $root -DirName 'full-code-review' -Body @'
# full-code-review

Runs only when the user explicitly requests an exhaustive review.
'@
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.Output -notmatch [regex]::Escape('skills/full-code-review/SKILL.md must explicitly claim workflow-owned report persistence.')) {
            throw "expected missing-ownership-claim failure for full-code-review. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Aggregate exit-code contract
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_ReportFailureSummary_When_AnySingleCheckFails' `
    -Arrange {
        $root = New-BaselineFixture
        New-AgentFile -Root $root -BaseName 'sample-agent' -Model 'not-a-real-model'
        $root
    } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.ExitCode -ne 1) { throw "expected exit 1, got $($r.ExitCode)" }
        if ($r.Output -notmatch '❌ \d+ configuration checks failed; \d+ passed\.') {
            throw "expected the aggregate failure summary line. Output: $($r.Output)"
        }
    }

Test-Case -Name 'Validator_Should_ReportSuccessSummary_When_NoChecksFail' `
    -Arrange { New-BaselineFixture } `
    -Act { param($root) Invoke-Validator -RepositoryRoot $root -SkipDockerCompose } `
    -Assert {
        param($r)
        if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode)" }
        if ($r.Output -notmatch '✅ All \d+ configuration checks passed\.') {
            throw "expected the aggregate success summary line. Output: $($r.Output)"
        }
    }

# ---------------------------------------------------------------------------
# Hermeticity guard: this suite must never mutate the active Copilot home.
# ---------------------------------------------------------------------------

Test-Case -Name 'Suite_Should_NeverWriteFixtureArtifacts_IntoActiveCopilotHome' `
    -Arrange { $null } `
    -Act { param($unused) [pscustomobject]@{ ExitCode = 0; Output = '' } } `
    -Assert {
        param($r)
        if (Test-Path -LiteralPath $sentinelAgentPath) {
            throw "fixture artifact 'sample-agent.md' was found under the active Copilot home ($sentinelAgentPath); a fixture must have leaked outside `$env:TEMP."
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
