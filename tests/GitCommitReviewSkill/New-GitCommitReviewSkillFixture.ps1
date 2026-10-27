#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$script:SkillsRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ValidatorPath = Join-Path $script:SkillsRepoRoot 'scripts\Validate-GitCommitReviewSkills.ps1'
$script:StandalonePolicySkills = @(
    'codebase-research', 'feature-design-doc', 'task-breakdown',
    'implementation-runner', 'dependency-audit-report', 'test-gap-audit'
)
Import-Module (Join-Path $script:SkillsRepoRoot 'scripts\IsolatedProcess.psm1') -ErrorAction Stop
$script:SkillFixtureContexts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

function New-BaselineSkillFixture {
    $context = New-IsolatedProcessContext
    $root = Join-Path $context.Root 'fixture'
    $script:SkillFixtureContexts.Add($root, $context)
    foreach ($name in @('git-commit-review', 'full-code-review') + $script:StandalonePolicySkills) {
        $destination = Join-Path $root "skills\$name"
        $null = New-Item -ItemType Directory -Path $destination -Force
        Copy-Item -LiteralPath (Join-Path $script:SkillsRepoRoot "skills\$name\SKILL.md") -Destination $destination
    }
    $instructionRoot = Join-Path $root 'instructions'
    $null = New-Item -ItemType Directory -Path $instructionRoot
    foreach ($name in @('workflow', 'git-conventions', 'work-lifecycle', 'coordination')) {
        Copy-Item -LiteralPath (Join-Path $script:SkillsRepoRoot "instructions\$name.instructions.md") -Destination $instructionRoot
    }
    $root
}

function Remove-FixtureRoot {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $script:SkillFixtureContexts.ContainsKey($Path)) { throw "Not an owned skill fixture: $Path" }
    Remove-IsolatedProcessContext -Context $script:SkillFixtureContexts[$Path]
    $null = $script:SkillFixtureContexts.Remove($Path)
}

function Get-ReviewPolicyMutations {
    @(
        @{
            Name = 'UndisclosedFidelityException'
            Find = 'risks before obtaining explicit user acceptance.'
            Replace = 'risks after continuing without acceptance.'
            Description = 'Permits disclosed candidate-specific fidelity exceptions'
        },
        @{
            Name = 'ExceptionReportedAsPass'
            Find = 'report the waived guarantee as **Accepted exception**, never passed.'
            Replace = 'report the waived guarantee as passed.'
            Description = 'Carries exceptions through later gates without claiming a pass'
        },
        @{
            Name = 'ExceptionWaivesRequiredChecks'
            Find = 'Preserve immutable tree bytes, candidate identity, required checks, and delivery controls.'
            Replace = 'Allow the exception to waive required checks and delivery controls.'
            Description = 'Preserves non-excepted guarantees and helper capability limits'
        },
        @{
            Name = 'StaleExceptionAcceptance'
            Find = 'refresh acceptance when either or the risks change.'
            Replace = 'reuse acceptance even when the candidate or risks change.'
            Description = 'Requires explicit refreshed exception acceptance and final commit approval'
        },
        @{
            Name = 'SnapshotCompleteness'
            Find = 'git ls-tree -r -z --full-tree'
            Replace = 'git ls-tree -z --full-tree'
            Description = 'Checks snapshot completeness against the captured tree'
        },
        @{
            Name = 'ChangedPathScope'
            Find = 'Use changed paths only for review scope, not snapshot completeness.'
            Replace = 'Use changed paths only for review scope, not snapshot correctness.'
            Description = 'Separates changed-path scope from snapshot completeness'
        },
        @{
            Name = 'ForbiddenChangedPathComparison'
            Find = 'Use changed paths only for review scope, not snapshot completeness.'
            Replace = 'Use changed paths only for review scope, not snapshot completeness. The materialized file list matches `git diff --cached --name-only`.'
            Description = 'Rejects the invalid changed-path snapshot comparison'
        },
        @{
            Name = 'FixRestageRebind'
            Find = 'rematerialize the snapshot using section 2'
            Replace = 'refresh the snapshot using section 2'
            Description = 'Rebinds fixed candidates to a new snapshot and affected checks'
        },
        @{
            Name = 'PreCommitTuple'
            Find = 'Immediately before committing, require'
            Replace = 'Later before committing, require'
            Description = 'Guards the complete candidate tuple before commit'
        },
        @{
            Name = 'CommittedTuple'
            Find = 'Verify the resulting commit tree, ordered parent list, destination ref, and ref state'
            Replace = 'Confirm the resulting commit tree, ordered parent list, destination ref, and ref state'
            Description = 'Verifies committed tree parents and destination'
        },
        @{
            Name = 'ApprovalTuple'
            Find = 'commit message **and that exact tuple**'
            Replace = 'commit message **only**'
            Description = 'Binds approval to the complete candidate tuple'
        },
        @{
            Name = 'WritingIntegrity'
            Find = 'Run each potentially writing preflight, restore, build, lint, or test command through'
            Replace = 'Run some read-only command through'
            Description = 'Checks tracked integrity around every writing command'
        },
        @{
            Name = 'FinalIntegrity'
            Find = 'After final validation and before final acceptance, require'
            Replace = 'Before final validation, require'
            Description = 'Rechecks tracked integrity before final acceptance'
        },
        @{
            Name = 'RestoredEvidence'
            Find = 'An observed failure is latched: restoring bytes does not clear it'
            Replace = 'An observed failure is cleared by restoring bytes'
            Description = 'Rejects retroactive evidence for restored bytes'
        },
        @{
            Name = 'RepositoryCapabilities'
            Find = 'presence of Copilot configuration alone does **not** imply'
            Replace = 'presence of Copilot configuration always implies'
            Description = 'Discovers target repository validation capabilities'
        },
        @{
            Name = 'RequiredInputs'
            Find = 'a declared required command or input that is missing must fail explicitly'
            Replace = 'a declared required command or input that is missing may be skipped'
            Description = 'Fails closed on missing declared validation inputs'
        },
        @{
            Name = 'CandidateArgument'
            Find = '$snapshot = New-GitTreeSnapshot -Candidate $candidate'
            Replace = '$snapshot = New-GitTreeSnapshot -Candidate $candidate -Tree HEAD'
            Description = 'Uses the shared executable snapshot procedure'
        },
        @{
            Name = 'HeadArchiveSubstitution'
            Find = '$snapshot = New-GitTreeSnapshot -Candidate $candidate'
            Replace = 'git archive --format=tar HEAD'
            Description = 'Uses the shared executable snapshot procedure'
        },
        @{
            Name = 'OmittedInitialIntegrity'
            Find = 'Assert-GitSnapshotIntegrity -Snapshot $snapshot -Exact'
            Replace = '# Integrity guard removed by a fixture mutation'
            Description = 'Uses the shared executable snapshot procedure'
        },
        @{
            Name = 'OmittedBaseContext'
            Find = '$baseSnapshot = New-GitTreeSnapshot -Candidate $candidate -Base'
            Replace = '# Base context omitted'
            Description = 'Uses the shared executable snapshot procedure'
        },
        @{
            Name = 'CandidateSubstitutedForBase'
            Find = '$baseSnapshot = New-GitTreeSnapshot -Candidate $candidate -Base'
            Replace = '$baseSnapshot = $snapshot'
            Description = 'Uses the shared executable snapshot procedure'
        },
        @{
            Name = 'IncompleteIntakeFields'
            Find = '| Locked requirements |'
            Replace = '| Optional requirements |'
            Description = 'Supplies complete immutable reviewer intake'
        },
        @{
            Name = 'CurrentFileSubstitution'
            Find = 'Never substitute current files for missing immutable review evidence.'
            Replace = 'Substitute current files for missing immutable review evidence.'
            Description = 'Rejects incomplete intake and current-file substitution'
        },
        @{
            Name = 'ReviewerWorkflowRestart'
            Find = 'without artifacts or workflow restart.'
            Replace = 'with workflow restart permitted.'
            Description = 'Keeps reviewer work bounded to the active caller'
        },
        @{
            Name = 'NestedTimeboxEscalation'
            Find = 'A requested `full-code-review` is a separate handoff only after this owning workflow has genuinely ended or been explicitly aborted'
            Replace = 'A requested `full-code-review` starts immediately inside this workflow'
            Description = 'Defers timebox escalation until the owning workflow ends'
        },
        @{
            Name = 'NestedRelatedSecurityAudit'
            Find = 'After this owning workflow ends, use `security-audit` only as a separate authorized workflow'
            Replace = 'During this owning workflow, invoke `security-audit` directly'
            Description = 'Keeps related terminal workflows as separate handoffs'
        },
        @{
            Name = 'FalseBlockedCompletion'
            Find = 'Never mark a blocked workflow complete merely to start another workflow.'
            Replace = 'Mark a blocked workflow complete to start another workflow.'
            Description = 'Preserves blocked workflow status across recommendations'
        },
        @{
            Name = 'ZeroSuitePass'
            Find = 'If no applicable suite exists, record **Not run - no applicable suite** and the coverage limitation, never a 0/0 pass.'
            Replace = 'If no applicable suite exists, record a 0/0 pass.'
            Description = 'Reports absent suites as not-run coverage limits'
        },
        @{
            Name = 'MissingRequiredCheckWaiver'
            Find = 'Missing declared pre-commit checks remain blockers; this not-run case does not waive required validation.'
            Replace = 'Missing declared pre-commit checks may be skipped.'
            Description = 'Keeps missing required checks blocking'
        },
        @{
            Name = 'SummaryReviewerCount'
            Find = 'Reviewers used, selection rationale, and cycle count: exactly one core, zero or one ordinary relevant specialist'
            Replace = 'Reviewers used, selection rationale, and cycle count: exactly one core and one mandatory ordinary specialist'
            Description = 'Summarizes consistent signal-driven reviewer counts'
        },
        @{
            Name = 'SpecialistRoleBoundary'
            Find = 'Each specialist uses a separate `code-reviewer` assignment with a domain focus and the same immutable intake and read/search-only boundary'
            Replace = 'Each specialist shares the core assignment and may edit the mutable working tree'
            Description = 'Preserves independent read-only domain assignments'
        },
        @{
            Name = 'UnconditionalFullSuite'
            Find = 'Run a full suite only when repository policy requires it or affected behavior'
            Replace = 'Run a full suite for every commit even when no affected behavior'
            Description = 'Makes full-suite scope depend on policy or impact'
        },
        @{
            Name = 'ImplicitCheckpoint'
            Find = 'An explicitly requested'
            Replace = 'An automatically selected'
            Description = 'Keeps checkpoints explicit and locally reviewed'
        },
        @{
            Name = 'DeferredPreCommitGate'
            Find = 'Required pre-commit checks cannot be deferred.'
            Replace = 'Required pre-commit checks may be deferred.'
            Description = 'Preserves repository pre-commit gates'
        },
        @{
            Name = 'FailedLocalCheckBypass'
            Find = 'Never defer failed checks on the current candidate or missing required local'
            Replace = 'Defer failed checks on the current candidate and missing required local'
            Description = 'Rejects failed-local-check checkpoint bypasses'
        },
        @{
            Name = 'LostPriorLiveFailure'
            Find = 'Failures from earlier revisions remain recorded;'
            Replace = 'Discard failures from earlier revisions;'
            Description = 'Keeps earlier live failures visible while allowing fix checkpoints'
        },
        @{
            Name = 'DuplicateSuspensionPrompt'
            Find = 'The checkpoint request supplies the suspension direction; do not ask twice.'
            Replace = 'A checkpoint request requires another suspension approval.'
            Description = 'Avoids a duplicate checkpoint suspension prompt'
        },
        @{
            Name = 'UnownedPendingValidation'
            Find = 'responsible owner, trigger and'
            Replace = 'unspecified future opportunity and'
            Description = 'Binds pending validation follow-up to the commit'
        },
        @{
            Name = 'CheckpointPushAuthority'
            Find = 'Checkpoint approval never authorizes push or deployment.'
            Replace = 'Checkpoint approval also authorizes push and deployment.'
            Description = 'Separates checkpoints from remote authorization'
        },
        @{
            Name = 'UnrelatedIndexReset'
            Find = 'Preserve unrelated staged and unstaged work; do not reset or restage it'
            Replace = 'Reset unrelated staged and unstaged work to simplify'
            Description = 'Preserves unrelated index and worktree changes'
        },
        @{
            Name = 'DocumentationBuildRequirement'
            Find = 'checks, not unrelated builds.'
            Replace = 'checks and unrelated builds.'
            Description = 'Limits documentation checks to applicable behavior'
        },
        @{
            Name = 'UnboundEvidenceReuse'
            Find = 'Reuse only successful snapshot-backed evidence for the same full candidate'
            Replace = 'Reuse any prior evidence without checking the candidate'
            Description = 'Constrains reused evidence to the exact validation context'
        },
        @{
            Name = 'WorktreeEvidenceSubstitution'
            Find = 'after invalidation are not reusable evidence.'
            Replace = 'after invalidation are reusable evidence.'
            Description = 'Rejects weaker evidence reuse substitutes'
        },
        @{
            Name = 'WordingEditedBeforeApproval'
            Find = 'replacement and obtain approval before applying or staging the wording change.'
            Replace = 'replacement and obtain approval after applying or staging the wording change.'
            Description = 'Requires approval before editing protected wording'
        },
        @{
            Name = 'DuplicateCommitConfirmation'
            Find = 'Use one confirmation for user verification and commit permission'
            Replace = 'Use two confirmations for user verification and commit permission'
            Description = 'Combines candidate verification and commit approval'
        },
        @{
            Name = 'DuplicateOutcomeRecords'
            Find = 'not duplicate timelines.'
            Replace = 'and duplicate the timeline.'
            Description = 'Keeps one durable review outcome'
        },
        @{
            Name = 'MandatoryMarkdownReport'
            Find = 'Write a Markdown report only when requested, repository-required, or no durable'
            Replace = 'Write a Markdown report for every commit even when a durable'
            Description = 'Avoids mandatory duplicate Markdown reports'
        },
        @{
            Name = 'RepeatedTaskAuthorization'
            Path = 'instructions\workflow.instructions.md'
            Find = 'necessary edits and local checks within its scope; do not ask again per phase.'
            Replace = 'necessary edits only after asking again for each phase.'
            Description = 'Honors clear task-scoped authorization'
        },
        @{
            Name = 'SharedWordingApprovalRemoved'
            Path = 'instructions\workflow.instructions.md'
            Find = 'exact replacement wording and obtain approval before applying or staging it.'
            Replace = 'replacement wording and apply or stage it before approval.'
            Description = 'Protects approval-controlled prose in the shared policy'
        },
        @{
            Name = 'GlobalBlocker'
            Path = 'instructions\workflow.instructions.md'
            Find = 'the operation requiring it, not independent authorized work.'
            Replace = 'all operations including independent authorized work.'
            Description = 'Scopes blockers to dependent operations'
        },
        @{
            Name = 'SharedDuplicateCommitApproval'
            Path = 'instructions\git-conventions.instructions.md'
            Find = 'obtain one explicit approval'
            Replace = 'obtain two explicit approvals'
            Description = 'Keeps shared commit approval singular and explicit'
        },
        @{
            Name = 'StaleEvidenceReuse'
            Path = 'instructions\work-lifecycle.instructions.md'
            Find = 'Reuse successful evidence only while those inputs and required freshness remain'
            Replace = 'Reuse evidence without establishing that inputs and freshness remain'
            Description = 'Preserves evidence freshness across phases'
        },
        @{
            Name = 'OverlappingSuspendedOwner'
            Path = 'instructions\coordination.instructions.md'
            Find = 'releases active ownership, and never marks'
            Replace = 'keeps active ownership, and never marks'
            Description = 'Suspends parents without completing blocked work'
        },
        @{
            Name = 'ChildApprovalDuplication'
            Path = 'instructions\coordination.instructions.md'
            Find = 'owner asks once, not again in each child.'
            Replace = 'owner asks once, then again in each child.'
            Description = 'Assigns transition approval to one owner'
        }
    )
    foreach ($name in $script:StandalonePolicySkills) {
        @{
            Name = "StandaloneBoundary-$name"
            Path = "skills\$name\SKILL.md"
            Find = 'Standalone, return'
            Replace = 'Standalone, expand'
            Description = "$name ends at the standalone outcome"
        }
    }
}

function Set-MutatedSkillContent {
    param([string]$Root, $Mutation)
    $relativePath = if ($Mutation.ContainsKey('Path')) { $Mutation.Path } else { 'skills\git-commit-review\SKILL.md' }
    $path = Join-Path $Root $relativePath
    $content = Get-Content -LiteralPath $path -Raw
    if (-not $content.Contains($Mutation.Find)) { throw "Mutation '$($Mutation.Name)' has no matching source text." }
    [IO.File]::WriteAllText($path, $content.Replace($Mutation.Find, $Mutation.Replace))
}

function Invoke-Validator {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$RelativeSkillRoot,
        [string]$InstructionRoot
    )
    $skillRoot = if ($RelativeSkillRoot) { 'skills' } else { Join-Path $Root 'skills' }
    $arguments = @('-NoProfile', '-File', $script:ValidatorPath, '-SkillRoot', $skillRoot)
    if ($PSBoundParameters.ContainsKey('InstructionRoot')) {
        $arguments += @('-InstructionRoot', $InstructionRoot)
    }
    Invoke-IsolatedProcess -Context $script:SkillFixtureContexts[$Root] -FilePath (Get-Command pwsh).Source `
        -WorkingDirectory $Root -ArgumentList $arguments -AllowFailure
}
