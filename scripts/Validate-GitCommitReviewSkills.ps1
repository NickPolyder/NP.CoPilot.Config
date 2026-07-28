<#
.SYNOPSIS
    Validates the Git review skill policy invariants.

.DESCRIPTION
    Checks the Markdown skill definitions for the lightweight and exhaustive
    review contracts. This script has no external dependencies and makes no
    changes, so it is safe to run repeatedly.

.PARAMETER SkillRoot
    Path to the skills directory. Defaults to this repository's skills directory.

.EXAMPLE
    .\scripts\Validate-GitCommitReviewSkills.ps1
#>

[CmdletBinding()]
param(
    [string]$SkillRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills')
)

$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0

function Write-Pass {
    param([Parameter(Mandatory)][string]$Description)

    $script:Passed++
    Write-Host "  ✅ $Description" -ForegroundColor Green
}

function Write-Fail {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Pattern
    )

    $script:Failed++
    Write-Host "  ❌ $Description (missing: $Pattern)" -ForegroundColor Red
}

function Assert-Pattern {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Description,
        [switch]$Absent
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $matched = [regex]::IsMatch($Content, $Pattern, $options)

    if ($matched -xor $Absent) {
        Write-Pass -Description $Description
        return
    }

    $expected = if ($Absent) { "forbidden: $Pattern" } else { $Pattern }
    Write-Fail -Description $Description -Pattern $expected
}

function Get-SkillContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Fail -Description $Description -Pattern $Path
        return $null
    }

    Write-Pass -Description $Description
    return Get-Content -LiteralPath $Path -Raw
}

$lightweightPath = Join-Path (Join-Path $SkillRoot 'git-commit-review') 'SKILL.md'
$fullPath = Join-Path (Join-Path $SkillRoot 'full-code-review') 'SKILL.md'

Write-Host ''
Write-Host '🔍 Validating Git review skill policy invariants...' -ForegroundColor Cyan

$lightweight = Get-SkillContent -Path $lightweightPath -Description 'Lightweight skill exists'
if ($null -ne $lightweight) {
    Write-Host '  Lightweight reviewer selection and escalation' -ForegroundColor Yellow
    Assert-Pattern -Content $lightweight -Pattern 'exactly one core reviewer:\s*`?code-reviewer`?' -Description 'Uses exactly one core code-reviewer'
    Assert-Pattern -Content $lightweight -Pattern 'at most one relevant specialist' -Description 'Limits normal review to one specialist'
    Assert-Pattern -Content $lightweight -Pattern 'second specialist only when two distinct high-risk domains' -Description 'Limits a second specialist to high-risk cross-domain work'
    Assert-Pattern -Content $lightweight -Pattern 'authentication.*authorization.*cryptography.*secrets' -Description 'Escalates authentication, authorization, cryptography, and secrets'
    Assert-Pattern -Content $lightweight -Pattern 'destructive or irreversible database migration' -Description 'Escalates destructive database migrations'
    Assert-Pattern -Content $lightweight -Pattern 'external production writes' -Description 'Escalates external production writes'
    Assert-Pattern -Content $lightweight -Pattern 'broad blast radius' -Description 'Escalates broad-blast-radius infrastructure changes'
    Assert-Pattern -Content $lightweight -Pattern 'safety-critical concurrency' -Description 'Escalates safety-critical concurrency changes'
    Assert-Pattern -Content $lightweight -Pattern 'data integrity' -Description 'Escalates data-integrity changes'
    Assert-Pattern -Content $lightweight -Pattern 'never invoke `full-code-review`' -Description 'Never auto-invokes full-code-review'

    Write-Host '  Lightweight clean-index preflight and cycle limits' -ForegroundColor Yellow
    Assert-Pattern -Content $lightweight -Pattern '(git write-tree.*git archive --format=tar|git checkout-index)' -Description 'Materializes the Git index with git write-tree and git archive'
    Assert-Pattern -Content $lightweight -Pattern 'snapshot cannot be materialized.*stop.*before launching any reviewer' -Description 'Blocks reviewers when clean-index preflight fails'
    Assert-Pattern -Content $lightweight -Pattern 'initial review is cycle one.*cycle two.*cycle three.*explicit approval' -Description 'Requires approval for every review cycle after two'
    Assert-Pattern -Content $lightweight -Pattern '(files modified|modified files).*previous finding locations.*directly affected contracts' -Description 'Scopes re-review to changed files, findings, and contracts'
    Assert-Pattern -Content $lightweight -Pattern 'full existing test suite once' -Description 'Runs the full test suite once at the final gate'
    Assert-Pattern -Content $lightweight -Pattern 'three[- ]hat' -Description 'Does not retain the deprecated three-hat workflow' -Absent
}

$full = Get-SkillContent -Path $fullPath -Description 'Full review skill exists'
if ($null -ne $full) {
    Write-Host '  Exhaustive review contract' -ForegroundColor Yellow
    Assert-Pattern -Content $full -Pattern 'only when the user explicitly requests' -Description 'Requires explicit user invocation'
    Assert-Pattern -Content $full -Pattern 'never.*automatically.*pre-commit' -Description 'Cannot run automatically during pre-commit work'
    Assert-Pattern -Content $full -Pattern 'Architect.*Principal Developer.*Senior Developer' -Description 'Uses all three exhaustive review hats'
    Assert-Pattern -Content $full -Pattern 'up to three specialists' -Description 'Limits exhaustive review to three specialists'
    Assert-Pattern -Content $full -Pattern 'Critical, High, Medium, or Low' -Description 'Includes every severity level'
    Assert-Pattern -Content $full -Pattern 'full-review-' -Description 'Persists a detailed full-review report'
}

Write-Host ''
if ($script:Failed -eq 0) {
    Write-Host "✅ All $script:Passed policy invariants passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $script:Failed of $($script:Passed + $script:Failed) policy invariants failed." -ForegroundColor Red
exit 1
