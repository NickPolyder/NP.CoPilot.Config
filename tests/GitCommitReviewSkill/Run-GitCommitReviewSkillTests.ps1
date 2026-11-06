#Requires -Version 7.0
<#
.SYNOPSIS
    Isolated wording/contract mutation tests, not proof of agent execution.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'New-GitCommitReviewSkillFixture.ps1')
$passed = 0
$failed = 0
$retiredMutations = @(
    'UndisclosedFidelityException', 'ExceptionReportedAsPass',
    'ExceptionWaivesRequiredChecks', 'StaleExceptionAcceptance',
    'OmittedBaseContext', 'CandidateSubstitutedForBase',
    'ChangedPathScope', 'ForbiddenChangedPathComparison',
    'CandidateArgument', 'HeadArchiveSubstitution', 'OmittedInitialIntegrity'
)
$policyMutations = @(
    Get-ReviewPolicyMutations | Where-Object { $_.Name -notin $retiredMutations }
) + @(
    @{
        Name = 'SelectedBaseContext'
        Find = '-Base -Paths $candidate.ChangedPaths'
        Replace = '-Base'
        Description = 'Uses complete candidate and selected base snapshots'
    },
    @{
        Name = 'CandidateSnapshotArgument'
        Find = '$snapshot = New-GitTreeSnapshot -Candidate $candidate'
        Replace = '$snapshot = New-GitTreeSnapshot -Candidate $candidate -Tree HEAD'
        Description = 'Uses complete candidate and selected base snapshots'
    },
    @{
        Name = 'CandidateSnapshotIntegrity'
        Find = 'Assert-GitSnapshotIntegrity -Snapshot $snapshot -Exact'
        Replace = '# Candidate snapshot integrity guard removed'
        Description = 'Uses complete candidate and selected base snapshots'
    },
    @{
        Name = 'BaseCandidateSubstitution'
        Find = '$baseSnapshot = New-GitTreeSnapshot -Candidate $candidate -Base -Paths $candidate.ChangedPaths'
        Replace = '$baseSnapshot = $snapshot'
        Description = 'Uses complete candidate and selected base snapshots'
    },
    @{
        Name = 'ArchiveSnapshotSubstitution'
        Find = '$snapshot = New-GitTreeSnapshot -Candidate $candidate'
        Replace = 'git archive --format=tar HEAD'
        Description = 'Uses complete candidate and selected base snapshots'
    },
    @{
        Name = 'ChangedPathCandidateScope'
        Find = 'The candidate snapshot is always complete; changed paths select the normal, minimal base context rather than limiting candidate completeness.'
        Replace = 'Changed paths limit candidate snapshot completeness.'
        Description = 'Keeps candidate completeness separate from selected base context'
    },
    @{
        Name = 'WindowsModeMetadata'
        Find = 'ModeFidelity` is `metadata-only`; on POSIX it is `exact`.'
        Replace = 'Mode fidelity is unavailable on Windows.'
        Description = 'Uses mode metadata on Windows and POSIX-required checks'
    },
    @{
        Name = 'ApprovalWaitRetention'
        Find = 'Do not ask a separate preliminary verification question or run approval in the background.'
        Replace = 'Start a background approval runner and rebuild context after it completes.'
        Description = 'Retains evidence during ordinary approval waits'
    },
    @{
        Name = 'StateRefreshScope'
        Find = 'Do not automatically rerun every check solely because the base or ref state changed.'
        Replace = 'Automatically rerun every check whenever base or ref state changes.'
        Description = 'Refreshes same-tree state without automatic full reruns'
    },
    @{
        Name = 'BaseGeneratedOutputBypass'
        Find = 'Ordinary generated outputs are allowed only in the candidate snapshot and never justify a base-context bypass or ignoring all base outputs.'
        Replace = 'Generated outputs may bypass all base-context checks.'
        Description = 'Keeps generated probes outside immutable base context'
    },
    @{
        Name = 'CleanupOutcome'
        Find = 'Report cleanup success or failure separately.'
        Replace = 'Treat cleanup failure as candidate failure.'
        Description = 'Separates cleanup status from verified commit outcome'
    },
    @{
        Name = 'KeywordReviewerFanOut'
        Find = 'rather than adding reviewers for'
        Replace = 'and automatically add reviewers for'
        Description = 'Uses domain focus without keyword-driven fan-out'
    },
    @{
        Name = 'UnrequestedExtraReviewer'
        Find = 'repository explicitly requires independent domain review or the user requests it.'
        Replace = 'repository has technology keywords.'
        Description = 'Requires repository or user authority for extra reviewers'
    },
    @{
        Name = 'PerPassReviewBudget'
        Find = 'one shared ten-minute review budget for initial review, findings'
        Replace = 'a fresh ten-minute review budget per pass for initial review, findings'
        Description = 'Shares ten minutes across all review passes'
    },
    @{
        Name = 'MissingReviewClock'
        Find = 'Record the start time and remaining budget before reviewer dispatch'
        Replace = 'Do not record elapsed review time'
        Description = 'Records elapsed review budget before dispatch'
    },
    @{
        Name = 'BudgetWaivesRequiredChecks'
        Find = 'are separate from review time;'
        Replace = 'must be skipped to meet review time;'
        Description = 'Distinguishes review time from checks fixes and approval waits'
    },
    @{
        Name = 'SilentBudgetExtension'
        Find = 'No silent extension, automatic'
        Replace = 'Allow silent extension and automatic'
        Description = 'Pauses incomplete review at the budget boundary'
    },
    @{
        Name = 'HiddenToolOverrun'
        Find = 'tool call that returns late is an overrun: report it and stop further review'
        Replace = 'tool call that returns late starts a fresh review budget'
        Description = 'Reports tool overruns without resetting the budget'
    },
    @{
        Name = 'WholeCodebaseCommitAudit'
        Find = 'Review only staged changes and directly affected contracts;'
        Replace = 'Review the whole codebase before every commit;'
        Description = 'Limits review to changed behavior and affected contracts'
    },
    @{
        Name = 'HypotheticalCommitBlocker'
        Find = 'A blocker needs a reachable failure, not a hypothetical future concern.'
        Replace = 'A hypothetical future concern is a blocker.'
        Description = 'Requires consequential reachable candidate defects'
    },
    @{
        Name = 'OptionalFindingFixCycle'
        Find = 'non-blocking follow-ups, never required polish or another fix cycle.'
        Replace = 'required fixes followed by another review cycle.'
        Description = 'Keeps optional findings out of blocking review cycles'
    },
    @{
        Name = 'FillReviewBudget'
        Find = 'no blockers; do not keep looking to fill the budget.'
        Replace = 'no blockers; keep looking until the budget is full.'
        Description = 'Stops early when focused review is complete'
    },
    @{
        Name = 'CycleResetsBudget'
        Find = 'Cycle permission does not reset the shared review budget.'
        Replace = 'Cycle permission resets the shared review budget.'
        Description = 'Prevents review-cycle budget resets'
    },
    @{
        Name = 'CleanReviewRestart'
        Find = 'When the initial review is clean, skip re-review entirely.'
        Replace = 'When the initial review is clean, start another review.'
        Description = 'Limits fix verification and skips clean re-review'
    },
    @{
        Name = 'PhaseOnlyEvidenceRerun'
        Find = 'Do not repeat successful checks or review solely because the workflow moved to'
        Replace = 'Repeat successful checks and review whenever the workflow moves to'
        Description = 'Rejects phase-only validation and review reruns'
    }
)
$cases = @(
    @{ Name = 'Unmodified positive control' },
    @{ Name = 'Relative skill root positive control'; RelativeSkillRoot = $true },
    @{ Name = 'Explicit instruction root positive control'; AlternateInstructionRoot = $true }
) + $policyMutations
Write-Host "`n🔍 Running review-policy wording regressions..." -ForegroundColor Cyan
foreach ($case in $cases) {
    try {
        $root = New-BaselineSkillFixture
        if ($case.ContainsKey('Find')) { Set-MutatedSkillContent -Root $root -Mutation $case }
        $arguments = @{ Root = $root }
        if ($case.ContainsKey('RelativeSkillRoot')) { $arguments.RelativeSkillRoot = $true }
        if ($case.ContainsKey('AlternateInstructionRoot')) {
            $arguments.InstructionRoot = Join-Path $root 'shared-policies'
            Move-Item -LiteralPath (Join-Path $root 'instructions') -Destination $arguments.InstructionRoot
        }
        $result = Invoke-Validator @arguments
        if ($case.ContainsKey('Find')) {
            if ($result.ExitCode -ne 1 -or $result.Output -notmatch [regex]::Escape("❌ $($case.Description)") -or
                $result.Output -notmatch '❌ 1 of \d+ policy invariants failed\.') {
                throw "Expected one named, nonzero failure for '$($case.Description)': $($result.Output)"
            }
        }
        else {
            if ($result.ExitCode -ne 0 -or $result.Output -notmatch '✅ All \d+ policy invariants passed\.') { throw $result.Output }
            foreach ($description in @($policyMutations | ForEach-Object Description | Sort-Object -Unique)) {
                if ($result.Output -notmatch [regex]::Escape("✅ $description")) { throw "Positive control did not check '$description'." }
            }
        }
        $passed++
        Write-Host "  ✅ $($case.Name)" -ForegroundColor Green
    }
    catch {
        $failed++
        Write-Host "  ❌ $($case.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        foreach ($owned in @($script:SkillFixtureContexts.Keys)) { Remove-FixtureRoot -Path $owned }
    }
}
if ($failed -eq 0) { Write-Host "`n✅ All $passed wording regression tests passed." -ForegroundColor Green; exit 0 }
Write-Host "`n❌ $failed of $($passed + $failed) wording regression tests failed." -ForegroundColor Red
exit 1
