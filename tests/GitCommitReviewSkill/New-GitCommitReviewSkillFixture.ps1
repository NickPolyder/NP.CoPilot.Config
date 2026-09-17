#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$script:SkillsRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ValidatorPath = Join-Path $script:SkillsRepoRoot 'scripts\Validate-GitCommitReviewSkills.ps1'
$script:LightweightSourcePath = Join-Path $script:SkillsRepoRoot 'skills\git-commit-review\SKILL.md'
$script:FullSourcePath = Join-Path $script:SkillsRepoRoot 'skills\full-code-review\SKILL.md'
Import-Module (Join-Path $script:SkillsRepoRoot 'scripts\IsolatedProcess.psm1') -ErrorAction Stop
$script:SkillFixtureContexts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

function New-BaselineSkillFixture {
    $context = New-IsolatedProcessContext
    $root = Join-Path $context.Root 'fixture'
    $script:SkillFixtureContexts.Add($root, $context)
    foreach ($name in @('git-commit-review', 'full-code-review')) {
        $destination = Join-Path $root "skills\$name"
        $null = New-Item -ItemType Directory -Path $destination -Force
        Copy-Item -LiteralPath (Join-Path $script:SkillsRepoRoot "skills\$name\SKILL.md") -Destination $destination
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
            Find = 'Missing declared required checks remain blockers; this not-run case does not waive required validation.'
            Replace = 'Missing declared required checks may be skipped.'
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
        }
    )
}

function Set-MutatedSkillContent {
    param([string]$Root, $Mutation)
    $content = Get-Content -LiteralPath $script:LightweightSourcePath -Raw
    if (-not $content.Contains($Mutation.Find)) { throw "Mutation '$($Mutation.Name)' has no matching source text." }
    [IO.File]::WriteAllText((Join-Path $Root 'skills\git-commit-review\SKILL.md'), $content.Replace($Mutation.Find, $Mutation.Replace))
}

function Invoke-Validator {
    param([Parameter(Mandatory)][string]$Root)
    Invoke-IsolatedProcess -Context $script:SkillFixtureContexts[$Root] -FilePath (Get-Command pwsh).Source `
        -WorkingDirectory $Root -ArgumentList @('-NoProfile', '-File', $script:ValidatorPath, '-SkillRoot', (Join-Path $Root 'skills')) -AllowFailure
}
