<#
.SYNOPSIS
    Validates the Git review skill policy invariants.

.DESCRIPTION
    Checks selected required and forbidden wording in the Markdown review
    contracts. These structural checks do not prove workflow execution or
    general semantic consistency. The script has no external dependencies and
    makes no changes, so it is safe to run repeatedly.

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
    Assert-Pattern -Content $lightweight -Pattern '<!-- tested-snapshot:start -->\r?\n```powershell\r?\nImport-Module \$snapshotHelper -ErrorAction Stop\r?\n\$candidate = New-GitReviewCandidate -RepositoryRoot \$repositoryRoot\r?\n\$snapshot = New-GitTreeSnapshot -Candidate \$candidate\r?\n\$baseSnapshot = New-GitTreeSnapshot -Candidate \$candidate -Base\r?\nAssert-GitSnapshotIntegrity -Snapshot \$snapshot -Exact\r?\nAssert-GitSnapshotIntegrity -Snapshot \$baseSnapshot -Exact\r?\nAssert-GitCandidateCurrent -Candidate \$candidate\r?\n```\r?\n<!-- tested-snapshot:end -->' -Description 'Uses the shared executable snapshot procedure'
    Assert-Pattern -Content $lightweight -Pattern 'Verify snapshot paths, file types, modes, and bytes against the captured tree.*git ls-tree -r -z --full-tree' -Description 'Checks snapshot completeness against the captured tree'
    Assert-Pattern -Content $lightweight -Pattern 'Use changed paths only for review scope, not snapshot completeness' -Description 'Separates changed-path scope from snapshot completeness'
    Assert-Pattern -Content $lightweight -Pattern 'materialized file list matches `git diff --cached --name-only`' -Description 'Rejects the invalid changed-path snapshot comparison' -Absent
    Assert-Pattern -Content $lightweight -Pattern 'stage only the approved fix hunks.*new tree ID.*rematerialize the snapshot.*affected validation and re-review' -Description 'Rebinds fixed candidates to a new snapshot and affected checks'
    Assert-Pattern -Content $lightweight -Pattern 'Immediately before committing, require `Assert-GitCandidateCurrent -Candidate \$candidate` and `Assert-GitSnapshotIntegrity -Snapshot \$snapshot`' -Description 'Guards the complete candidate tuple before commit'
    Assert-Pattern -Content $lightweight -Pattern 'Verify the resulting commit tree, ordered parent list, destination ref, and ref state using `Assert-GitCandidateCommit' -Description 'Verifies committed tree parents and destination'
    Assert-Pattern -Content $lightweight -Pattern 'approval for the proposed conventional commit message \*\*and that exact tuple\*\*' -Description 'Binds approval to the complete candidate tuple'
    Assert-Pattern -Content $lightweight -Pattern 'Run each potentially writing preflight, restore, build, lint, or test command through `Invoke-GitSnapshotCheck`' -Description 'Checks tracked integrity around every writing command'
    Assert-Pattern -Content $lightweight -Pattern 'After final validation and before final acceptance, require `Assert-GitSnapshotIntegrity -Snapshot \$snapshot` and `Assert-GitCandidateCurrent -Candidate \$candidate`' -Description 'Rechecks tracked integrity before final acceptance'
    Assert-Pattern -Content $lightweight -Pattern 'An observed failure is latched: restoring bytes does not clear it' -Description 'Rejects retroactive evidence for restored bytes'
    Assert-Pattern -Content $lightweight -Pattern 'presence of Copilot configuration alone does \*\*not\*\* imply' -Description 'Discovers target repository validation capabilities'
    Assert-Pattern -Content $lightweight -Pattern 'a declared required command or input that is missing must fail explicitly' -Description 'Fails closed on missing declared validation inputs'
    Assert-Pattern -Content $lightweight -Pattern 'snapshot cannot be materialized.*stop.*before launching any reviewer' -Description 'Blocks reviewers when clean-index preflight fails'
    Assert-Pattern -Content $lightweight -Pattern 'initial review is cycle one.*cycle two.*cycle three.*explicit approval' -Description 'Requires approval for every review cycle after two'
    Assert-Pattern -Content $lightweight -Pattern '(files modified|modified files).*previous finding locations.*directly affected contracts' -Description 'Scopes re-review to changed files, findings, and contracts'
    Assert-Pattern -Content $lightweight -Pattern 'full existing test suite once' -Description 'Runs the full test suite once at the final gate'
    Assert-Pattern -Content $lightweight -Pattern 'Before dispatch, this active caller must supply the complete reviewer intake:.*?\| Repository and scope \|[^\r\n]*\r?\n\| Resolved identities \|[^\r\n]*\r?\n\| Complete diff and frozen context \|[^\r\n]*\r?\n\| Locked requirements \|[^\r\n]*\r?\n\| Validation evidence \|' -Description 'Supplies complete immutable reviewer intake'
    Assert-Pattern -Content $lightweight -Pattern 'Missing or unreadable required intake means \*\*Incomplete - missing evidence\*\*.*Never substitute current files for missing immutable review evidence' -Description 'Rejects incomplete intake and current-file substitution'
    Assert-Pattern -Content $lightweight -Pattern '`code-reviewer` has `read` and `search` only; it returns bounded findings and evidence gaps to this active caller, without artifacts or workflow restart' -Description 'Keeps reviewer work bounded to the active caller'
    Assert-Pattern -Content $lightweight -Pattern 'If review coverage is incomplete.*A requested `full-code-review` is a separate handoff only after this owning workflow has genuinely ended or been explicitly aborted' -Description 'Defers timebox escalation until the owning workflow ends'
    Assert-Pattern -Content $lightweight -Pattern '## Related skills and agents.*After this owning workflow ends, use `full-code-review` only by separate explicit user invocation.*After this owning workflow ends, use `security-audit` only as a separate authorized workflow' -Description 'Keeps related terminal workflows as separate handoffs'
    Assert-Pattern -Content $lightweight -Pattern 'Never mark a blocked workflow complete merely to start another workflow' -Description 'Preserves blocked workflow status across recommendations'
    Assert-Pattern -Content $lightweight -Pattern 'If no applicable suite exists, record \*\*Not run - no applicable suite\*\* and the coverage limitation, never a 0/0 pass' -Description 'Reports absent suites as not-run coverage limits'
    Assert-Pattern -Content $lightweight -Pattern 'Missing declared required checks remain blockers; this not-run case does not waive required validation' -Description 'Keeps missing required checks blocking'
    Assert-Pattern -Content $lightweight -Pattern 'Reviewers used, selection rationale, and cycle count: exactly one core, zero or one ordinary relevant specialist, required signal-driven expertise, and a second specialist only for directly interacting distinct high-risk domains' -Description 'Summarizes consistent signal-driven reviewer counts'
    Assert-Pattern -Content $lightweight -Pattern 'Each specialist uses a separate `code-reviewer` assignment with a domain focus and the same immutable intake and read/search-only boundary' -Description 'Preserves independent read-only domain assignments'
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
