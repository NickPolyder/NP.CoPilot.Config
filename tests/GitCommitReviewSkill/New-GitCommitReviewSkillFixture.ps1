#Requires -Version 7.0
<#
.SYNOPSIS
    Builds isolated, disposable fixture trees for
    scripts\Validate-GitCommitReviewSkills.ps1 tests.
.DESCRIPTION
    No side effects outside $env:TEMP. Every helper here only ever writes to
    a caller-supplied fixture root; the real repository's
    skills\git-commit-review\SKILL.md and skills\full-code-review\SKILL.md
    are only ever read, never modified. Callers must remove the returned
    fixture root when done (Remove-FixtureRoot / try-finally).
#>

$ErrorActionPreference = 'Stop'

# tests\GitCommitReviewSkill\New-GitCommitReviewSkillFixture.ps1 -> repo root
# is two levels up.
$script:SkillsRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ValidatorPath = Join-Path $script:SkillsRepoRoot 'scripts\Validate-GitCommitReviewSkills.ps1'
$script:LightweightSourcePath = Join-Path $script:SkillsRepoRoot 'skills\git-commit-review\SKILL.md'
$script:FullSourcePath = Join-Path $script:SkillsRepoRoot 'skills\full-code-review\SKILL.md'

function New-FixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory to use as an isolated
        -SkillRoot. Caller is responsible for cleanup.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-gcr-skill-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null
    $path
}

function Remove-FixtureRoot {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-SourceLightweightSkillContent {
    <#
    .SYNOPSIS
        Returns the real repository's current git-commit-review\SKILL.md
        content, read-only. Used as the mutation base for negative cases so
        every unrelated invariant stays intact.
    #>
    Get-Content -LiteralPath $script:LightweightSourcePath -Raw
}

function New-BaselineSkillFixture {
    <#
    .SYNOPSIS
        Copies the real, unmodified git-commit-review and full-code-review
        SKILL.md files into a fresh fixture root's skills directory. Passes
        every Validate-GitCommitReviewSkills.ps1 check. Callers mutate the
        lightweight file's content with Set-LightweightSkillContent to build
        a single-behavior negative case.
    #>
    $root = New-FixtureRoot

    $lightweightDir = Join-Path $root 'skills\git-commit-review'
    $fullDir = Join-Path $root 'skills\full-code-review'
    New-Item -ItemType Directory -Path $lightweightDir -Force | Out-Null
    New-Item -ItemType Directory -Path $fullDir -Force | Out-Null

    Copy-Item -LiteralPath $script:LightweightSourcePath -Destination (Join-Path $lightweightDir 'SKILL.md') -Force
    Copy-Item -LiteralPath $script:FullSourcePath -Destination (Join-Path $fullDir 'SKILL.md') -Force

    $root
}

function Set-LightweightSkillContent {
    <#
    .SYNOPSIS
        Overwrites the fixture's git-commit-review\SKILL.md content, e.g.
        with a single targeted mutation of the real source text.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Content
    )

    $path = Join-Path $Root 'skills\git-commit-review\SKILL.md'
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8 -NoNewline
}

function Get-MutatedLightweightSkillContent {
    <#
    .SYNOPSIS
        Returns the real source content with exactly one required phrase
        broken, or the forbidden legacy phrase reintroduced, so a single
        Validate-GitCommitReviewSkills.ps1 structural check fails while every
        other invariant stays intact. Throws if the expected source text is
        not found, so a future SKILL.md edit fails loudly instead of
        silently producing a no-op mutation.
    .PARAMETER Mutation
        Which of the six new structural invariants to break:
        SnapshotCompletenessCheck, ChangedPathScopeSeparation,
        ReintroduceForbiddenChangedPathComparison, FixRestageRebind,
        PreCommitTreeGuard, CommittedTreeVerification.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'SnapshotCompletenessCheck',
            'ChangedPathScopeSeparation',
            'ReintroduceForbiddenChangedPathComparison',
            'FixRestageRebind',
            'PreCommitTreeGuard',
            'CommittedTreeVerification'
        )]
        [string]$Mutation
    )

    $content = Get-SourceLightweightSkillContent

    $replacement = switch ($Mutation) {
        'SnapshotCompletenessCheck' {
            @{
                Find    = 'git ls-tree -r --full-tree $tree'
                Replace = 'git ls-tree --full-tree $tree'
            }
        }
        'ChangedPathScopeSeparation' {
            @{
                Find    = 'Use changed paths only for review scope, not snapshot completeness.'
                Replace = 'Use changed paths only for review scope, not snapshot correctness.'
            }
        }
        'ReintroduceForbiddenChangedPathComparison' {
            @{
                Find    = 'Re-run `git write-tree` and require it to equal `$tree` before accepting the captured diff and snapshot as one candidate.'
                Replace = 'Confirm the materialized file list matches `git diff --cached --name-only`. Re-run `git write-tree` and require it to equal `$tree` before accepting the captured diff and snapshot as one candidate.'
            }
        }
        'FixRestageRebind' {
            @{
                Find    = 'rematerialize the snapshot using section 2'
                Replace = 'refresh the snapshot using section 2'
            }
        }
        'PreCommitTreeGuard' {
            @{
                Find    = 'Immediately before committing, require `git write-tree` to equal the final validated tree ID.'
                Replace = 'Just before committing, require `git write-tree` to equal the final validated tree ID.'
            }
        }
        'CommittedTreeVerification' {
            @{
                Find    = 'Verify the resulting commit tree equals the validated tree ID'
                Replace = 'Confirm the resulting commit tree equals the validated tree ID'
            }
        }
    }

    if (-not $content.Contains($replacement.Find)) {
        throw "Fixture mutation '$Mutation' expected to find the literal source text '$($replacement.Find)' in $script:LightweightSourcePath, but it was not present. The real SKILL.md wording may have changed; update this fixture's mutation text to match."
    }

    $content.Replace($replacement.Find, $replacement.Replace)
}

function Invoke-Validator {
    <#
    .SYNOPSIS
        Runs Validate-GitCommitReviewSkills.ps1 out-of-process against an
        isolated fixture's skills directory. Returns exit code + combined
        stdout/stderr.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $skillRoot = Join-Path $Root 'skills'
    $allArgs = @('-NoProfile', '-File', $script:ValidatorPath, '-SkillRoot', $skillRoot)
    $output = & pwsh @allArgs 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}
