<#
.SYNOPSIS
    Validates the Git review skill policy invariants.

.DESCRIPTION
    Checks selected required and forbidden wording in the Markdown review
    contracts, shared policy owners, and affected daily-work skills.
    These structural checks do not prove workflow execution or
    general semantic consistency. The script has no external dependencies and
    makes no changes, so it is safe to run repeatedly.

.PARAMETER SkillRoot
    Path to the skills directory. Defaults to this repository's skills directory.

.PARAMETER InstructionRoot
    Path to the shared policy owners. Defaults to the instructions directory
    beside SkillRoot; custom fixtures must supply those contracts too.

.EXAMPLE
    .\scripts\Validate-GitCommitReviewSkills.ps1
#>

[CmdletBinding()]
param(
    [string]$SkillRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills'),

    [string]$InstructionRoot = (Join-Path $SkillRoot '..\instructions')
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

function Get-PolicyContent {
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

$lightweight = Get-PolicyContent -Path $lightweightPath -Description 'Lightweight skill exists'
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
    Assert-Pattern -Content $lightweight -Pattern 'Run a full suite only when repository policy requires it or affected behavior\s+warrants that scope' -Description 'Makes full-suite scope depend on policy or impact'
    Assert-Pattern -Content $lightweight -Pattern 'Before dispatch, this active caller must supply the complete reviewer intake:.*?\| Repository and scope \|[^\r\n]*\r?\n\| Resolved identities \|[^\r\n]*\r?\n\| Complete diff and frozen context \|[^\r\n]*\r?\n\| Locked requirements \|[^\r\n]*\r?\n\| Validation evidence \|' -Description 'Supplies complete immutable reviewer intake'
    Assert-Pattern -Content $lightweight -Pattern 'Missing or unreadable required intake means \*\*Incomplete - missing evidence\*\*.*Never substitute current files for missing immutable review evidence' -Description 'Rejects incomplete intake and current-file substitution'
    Assert-Pattern -Content $lightweight -Pattern '`code-reviewer` has `read` and `search` only; it returns bounded findings and evidence gaps to this active caller, without artifacts or workflow restart' -Description 'Keeps reviewer work bounded to the active caller'
    Assert-Pattern -Content $lightweight -Pattern 'If review coverage is incomplete.*A requested `full-code-review` is a separate handoff only after this owning workflow has genuinely ended or been explicitly aborted' -Description 'Defers timebox escalation until the owning workflow ends'
    Assert-Pattern -Content $lightweight -Pattern '## Related skills and agents.*After this owning workflow ends, use `full-code-review` only by separate explicit user invocation.*After this owning workflow ends, use `security-audit` only as a separate authorized workflow' -Description 'Keeps related terminal workflows as separate handoffs'
    Assert-Pattern -Content $lightweight -Pattern 'Never mark a blocked workflow complete merely to start another workflow' -Description 'Preserves blocked workflow status across recommendations'
    Assert-Pattern -Content $lightweight -Pattern 'If no applicable suite exists, record \*\*Not run - no applicable suite\*\* and the coverage limitation, never a 0/0 pass' -Description 'Reports absent suites as not-run coverage limits'
    Assert-Pattern -Content $lightweight -Pattern 'Missing declared pre-commit checks remain blockers; this not-run case does not waive required validation' -Description 'Keeps missing required checks blocking'
    Assert-Pattern -Content $lightweight -Pattern 'Reviewers used, selection rationale, and cycle count: exactly one core, zero or one ordinary relevant specialist, required signal-driven expertise, and a second specialist only for directly interacting distinct high-risk domains' -Description 'Summarizes consistent signal-driven reviewer counts'
    Assert-Pattern -Content $lightweight -Pattern 'Each specialist uses a separate `code-reviewer` assignment with a domain focus and the same immutable intake and read/search-only boundary' -Description 'Preserves independent read-only domain assignments'
    Assert-Pattern -Content $lightweight -Pattern 'three[- ]hat' -Description 'Does not retain the deprecated three-hat workflow' -Absent

    Write-Host '  Daily commit boundaries and evidence' -ForegroundColor Yellow
    Assert-Pattern -Content $lightweight -Pattern 'An explicitly requested\s+\*\*checkpoint commit\*\* uses the same snapshot, local-check, review and approval\s+gates' -Description 'Keeps checkpoints explicit and locally reviewed'
    Assert-Pattern -Content $lightweight -Pattern 'Required pre-commit checks cannot be deferred' -Description 'Preserves repository pre-commit gates'
    Assert-Pattern -Content $lightweight -Pattern 'Never defer failed checks on the current candidate or missing required local\s+commands/inputs' -Description 'Rejects failed-local-check checkpoint bypasses'
    Assert-Pattern -Content $lightweight -Pattern 'Failures from earlier revisions remain recorded; a changed\s+fix may need a pending live retest' -Description 'Keeps earlier live failures visible while allowing fix checkpoints'
    Assert-Pattern -Content $lightweight -Pattern 'The checkpoint request supplies the suspension direction; do not ask twice' -Description 'Avoids a duplicate checkpoint suspension prompt'
    Assert-Pattern -Content $lightweight -Pattern 'Pending - post-commit/live validation.*?responsible owner, trigger.*?acceptance gate.*?resulting commit SHA' -Description 'Binds pending validation follow-up to the commit'
    Assert-Pattern -Content $lightweight -Pattern 'Checkpoint approval never authorizes push or deployment' -Description 'Separates checkpoints from remote authorization'
    Assert-Pattern -Content $lightweight -Pattern 'Preserve unrelated staged and unstaged work; do not reset or restage it' -Description 'Preserves unrelated index and worktree changes'
    Assert-Pattern -Content $lightweight -Pattern 'Documentation-only candidates need applicable documentation/configuration\s+checks, not unrelated builds' -Description 'Limits documentation checks to applicable behavior'
    Assert-Pattern -Content $lightweight -Pattern 'Reuse only successful snapshot-backed evidence for the same full candidate\s+tuple.*?required freshness.*?Reused - passed' -Description 'Constrains reused evidence to the exact validation context'
    Assert-Pattern -Content $lightweight -Pattern 'Worktree-only results, tree equality without the full tuple, and restored bytes\s+after invalidation are not reusable evidence' -Description 'Rejects weaker evidence reuse substitutes'
    Assert-Pattern -Content $lightweight -Pattern 'For approval-controlled prose, present the exact proposed\s+replacement and obtain approval before applying or staging the wording change' -Description 'Requires approval before editing protected wording'
    Assert-Pattern -Content $lightweight -Pattern 'Use one confirmation for user verification and commit permission' -Description 'Combines candidate verification and commit approval'
    Assert-Pattern -Content $lightweight -Pattern 'Keep one\s+durable outcome record.*?not duplicate timelines' -Description 'Keeps one durable review outcome'
    Assert-Pattern -Content $lightweight -Pattern 'Write a Markdown report only when requested, repository-required, or no durable\s+provider is available' -Description 'Avoids mandatory duplicate Markdown reports'
}

$full = Get-PolicyContent -Path $fullPath -Description 'Full review skill exists'
if ($null -ne $full) {
    Write-Host '  Exhaustive review contract' -ForegroundColor Yellow
    Assert-Pattern -Content $full -Pattern 'only when the user explicitly requests' -Description 'Requires explicit user invocation'
    Assert-Pattern -Content $full -Pattern 'never.*automatically.*pre-commit' -Description 'Cannot run automatically during pre-commit work'
    Assert-Pattern -Content $full -Pattern 'Architect.*Principal Developer.*Senior Developer' -Description 'Uses all three exhaustive review hats'
    Assert-Pattern -Content $full -Pattern 'up to three specialists' -Description 'Limits exhaustive review to three specialists'
    Assert-Pattern -Content $full -Pattern 'Critical, High, Medium, or Low' -Description 'Includes every severity level'
    Assert-Pattern -Content $full -Pattern 'full-review-' -Description 'Persists a detailed full-review report'
}

Write-Host '  Shared daily-work policy owners' -ForegroundColor Yellow
$workflow = Get-PolicyContent -Path (Join-Path $InstructionRoot 'workflow.instructions.md') -Description 'Workflow policy exists'
if ($null -ne $workflow) {
    Assert-Pattern -Content $workflow -Pattern 'A clear request authorizes\s+necessary edits and local checks within its scope; do not ask again per phase' -Description 'Honors clear task-scoped authorization'
    Assert-Pattern -Content $workflow -Pattern 'exact replacement wording and obtain approval before applying or staging it' -Description 'Protects approval-controlled prose in the shared policy'
    Assert-Pattern -Content $workflow -Pattern 'blocks\s+the operation requiring it, not independent authorized work' -Description 'Scopes blockers to dependent operations'
}
$delivery = Get-PolicyContent -Path (Join-Path $InstructionRoot 'git-conventions.instructions.md') -Description 'Delivery policy exists'
if ($null -ne $delivery) {
    Assert-Pattern -Content $delivery -Pattern 'obtain one explicit approval\s+covering changes and message' -Description 'Keeps shared commit approval singular and explicit'
}
$lifecycle = Get-PolicyContent -Path (Join-Path $InstructionRoot 'work-lifecycle.instructions.md') -Description 'Evidence policy exists'
if ($null -ne $lifecycle) {
    Assert-Pattern -Content $lifecycle -Pattern 'Reuse successful evidence only while those inputs and required freshness remain\s+valid' -Description 'Preserves evidence freshness across phases'
}
$coordination = Get-PolicyContent -Path (Join-Path $InstructionRoot 'coordination.instructions.md') -Description 'Coordination policy exists'
if ($null -ne $coordination) {
    Assert-Pattern -Content $coordination -Pattern 'owner and any parent to finish, or\s+explicit user-directed suspension for a checkpoint commit.*?releases active ownership, and never marks\s+blocked work complete' -Description 'Suspends parents without completing blocked work'
    Assert-Pattern -Content $coordination -Pattern 'Requested coordinators retain their gates; the\s+owner asks once, not again in each child' -Description 'Assigns transition approval to one owner'
}

Write-Host '  Standalone skill boundaries' -ForegroundColor Yellow
foreach ($name in @('codebase-research', 'feature-design-doc', 'task-breakdown', 'implementation-runner', 'dependency-audit-report', 'test-gap-audit')) {
    $content = Get-PolicyContent -Path (Join-Path $SkillRoot "$name\SKILL.md") -Description "$name skill exists"
    if ($null -ne $content) {
        Assert-Pattern -Content $content -Pattern 'Standalone, return.*?\band stop; do not prompt' -Description "$name ends at the standalone outcome"
    }
}

Write-Host ''
if ($script:Failed -eq 0) {
    Write-Host "✅ All $script:Passed policy invariants passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $script:Failed of $($script:Passed + $script:Failed) policy invariants failed." -ForegroundColor Red
exit 1
