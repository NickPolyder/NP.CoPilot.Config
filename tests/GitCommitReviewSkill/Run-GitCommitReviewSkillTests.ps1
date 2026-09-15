#Requires -Version 7.0
<#
.SYNOPSIS
    Deterministic, dependency-free regression suite for
    scripts\Validate-GitCommitReviewSkills.ps1's six structural invariants
    added for the staged-review snapshot/rematerialization fixes.
.DESCRIPTION
    Invokes the validator out-of-process against disposable fixtures under
    $env:TEMP, built from read-only copies of the real
    skills\git-commit-review\SKILL.md and skills\full-code-review\SKILL.md.
    These are wording checks against the Markdown contract text, not proof
    of agent behavior; tests\GitCommitReviewSkill\Run-GitSnapshotProcedureTests.ps1
    separately verifies the documented Git procedure itself against a real
    isolated repository. No Pester, no third-party dependency. Mirrors the
    conventions established by tests\ValidateConfig\Run-ValidateConfigTests.ps1.
.EXAMPLE
    pwsh -NoProfile -File .\tests\GitCommitReviewSkill\Run-GitCommitReviewSkillTests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:TestsPassed = 0
$script:TestsFailed = 0

. (Join-Path $PSScriptRoot 'New-GitCommitReviewSkillFixture.ps1')

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
        if ($arranged -and (Test-Path -LiteralPath $arranged -PathType Container)) {
            Remove-FixtureRoot -Path $arranged
        }
    }
}

Write-Host ''
Write-Host '🔍 Running Validate-GitCommitReviewSkills.ps1 regression suite...' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Positive: the real, unmodified SKILL.md content satisfies all six new
# structural invariants (and every pre-existing one).
# ---------------------------------------------------------------------------

Test-Case -Name 'Validator_Should_PassAllSixNewInvariants_When_SkillContentIsUnmodified' `
    -Arrange { New-BaselineSkillFixture } `
    -Act { param($root) Invoke-Validator -Root $root } `
    -Assert {
        param($r)
        if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
        if ($r.Output -notmatch '✅ All \d+ policy invariants passed\.') {
            throw "expected the aggregate success summary line. Output: $($r.Output)"
        }
        $expectedPassLines = @(
            'Checks snapshot completeness against the captured tree',
            'Separates changed-path scope from snapshot completeness',
            'Rejects the invalid changed-path snapshot comparison',
            'Rebinds fixed candidates to a new snapshot and affected checks',
            'Guards the final candidate tree before commit',
            'Verifies the committed tree identity'
        )
        foreach ($line in $expectedPassLines) {
            if ($r.Output -notmatch [regex]::Escape("✅ $line")) {
                throw "expected a passing line for '$line'. Output: $($r.Output)"
            }
        }
    }

# ---------------------------------------------------------------------------
# Negative mutations: one isolated behavior broken per case, all other
# invariants (including the other five new ones) must still pass.
# ---------------------------------------------------------------------------

$mutationCases = @(
    @{
        Mutation    = 'SnapshotCompletenessCheck'
        TestName    = 'Validator_Should_FailSnapshotCompletenessCheck_When_LsTreeRecursiveFlagIsDropped'
        Description = 'Checks snapshot completeness against the captured tree'
    },
    @{
        Mutation    = 'ChangedPathScopeSeparation'
        TestName    = 'Validator_Should_FailChangedPathScopeSeparationCheck_When_CompletenessWordingIsAltered'
        Description = 'Separates changed-path scope from snapshot completeness'
    },
    @{
        Mutation    = 'ReintroduceForbiddenChangedPathComparison'
        TestName    = 'Validator_Should_FailForbiddenComparisonCheck_When_LegacyWordingIsReintroduced'
        Description = 'Rejects the invalid changed-path snapshot comparison'
    },
    @{
        Mutation    = 'FixRestageRebind'
        TestName    = 'Validator_Should_FailFixRestageRebindCheck_When_RematerializeWordingIsWeakened'
        Description = 'Rebinds fixed candidates to a new snapshot and affected checks'
    },
    @{
        Mutation    = 'PreCommitTreeGuard'
        TestName    = 'Validator_Should_FailPreCommitTreeGuardCheck_When_ImmediatelyWordingIsWeakened'
        Description = 'Guards the final candidate tree before commit'
    },
    @{
        Mutation    = 'CommittedTreeVerification'
        TestName    = 'Validator_Should_FailCommittedTreeVerificationCheck_When_VerifyWordingIsWeakened'
        Description = 'Verifies the committed tree identity'
    }
)

foreach ($case in $mutationCases) {
    Test-Case -Name $case.TestName `
        -Arrange {
            $root = New-BaselineSkillFixture
            $mutated = Get-MutatedLightweightSkillContent -Mutation $case.Mutation
            Set-LightweightSkillContent -Root $root -Content $mutated
            $root
        } `
        -Act { param($root) Invoke-Validator -Root $root } `
        -Assert {
            param($r)
            if ($r.ExitCode -ne 1) { throw "expected exit 1 for a broken invariant, got $($r.ExitCode). Output: $($r.Output)" }
            if ($r.Output -notmatch [regex]::Escape("❌ $($case.Description)")) {
                throw "expected a named failure line for '$($case.Description)'. Output: $($r.Output)"
            }
            if ($r.Output -match '✅ All \d+ policy invariants passed\.') {
                throw "the mutated fixture must not report full success. Output: $($r.Output)"
            }
            if ($r.Output -notmatch '❌ 1 of \d+ policy invariants failed\.') {
                throw "expected exactly one failing invariant for this isolated mutation. Output: $($r.Output)"
            }
        }
}

Write-Host ''
if ($script:TestsFailed -eq 0) {
    Write-Host "✅ All $script:TestsPassed tests passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $script:TestsFailed of $($script:TestsPassed + $script:TestsFailed) tests failed." -ForegroundColor Red
exit 1
