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
$cases = @(@{ Name = 'Unmodified positive control' }) + @(Get-ReviewPolicyMutations)
Write-Host "`n🔍 Running review-policy wording regressions..." -ForegroundColor Cyan
foreach ($case in $cases) {
    try {
        $root = New-BaselineSkillFixture
        if ($case.ContainsKey('Find')) { Set-MutatedSkillContent -Root $root -Mutation $case }
        $result = Invoke-Validator -Root $root
        if ($case.ContainsKey('Find')) {
            if ($result.ExitCode -ne 1 -or $result.Output -notmatch [regex]::Escape("❌ $($case.Description)") -or
                $result.Output -notmatch '❌ 1 of \d+ policy invariants failed\.') {
                throw "Expected one named, nonzero failure for '$($case.Description)': $($result.Output)"
            }
        }
        else {
            if ($result.ExitCode -ne 0 -or $result.Output -notmatch '✅ All \d+ policy invariants passed\.') { throw $result.Output }
            foreach ($description in @(Get-ReviewPolicyMutations | ForEach-Object Description | Sort-Object -Unique)) {
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
