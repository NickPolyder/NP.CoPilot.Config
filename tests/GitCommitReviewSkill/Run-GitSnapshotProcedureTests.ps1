#Requires -Version 7.0
<#
.SYNOPSIS
    Deterministic regression suite verifying the actual Git semantics of the
    staged-index snapshot procedure documented in
    skills\git-commit-review\SKILL.md sections 2 and 7, against a real,
    isolated Git repository.
.DESCRIPTION
    This suite does not exercise a production script — the procedure it
    verifies is a documented sequence of Git commands an agent follows, not
    code owned by this repository. It runs that exact sequence
    (git write-tree, git ls-tree, git diff --cached, git archive + tar)
    against a disposable repository under $env:TEMP to prove the documented
    claims hold under real Git semantics: an unchanged tracked file survives
    in the full snapshot tree, added/changed/deleted/renamed paths behave as
    documented, unstaged working-tree edits are excluded from both the tree
    and the materialized snapshot, and restaging an approved fix produces a
    new candidate tree distinct from the one it replaces. No repository
    source file is modified; no live index of this repository is touched.
    No Pester, no third-party dependency, only the `git` and `tar` this
    repository's own tooling already depends on.
.EXAMPLE
    pwsh -NoProfile -File .\tests\GitCommitReviewSkill\Run-GitSnapshotProcedureTests.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:TestsPassed = 0
$script:TestsFailed = 0

. (Join-Path $PSScriptRoot 'New-GitSnapshotFixture.ps1')

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
    <#
    .SYNOPSIS
        Runs one AAA-structured test case with automatic fixture cleanup.
        Arrange/Act may return an object exposing a .CleanupPaths array
        (one or more disposable temp paths: repo root, snapshot dir,
        archive file); whichever paths are present are removed afterwards.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Arrange,
        [Parameter(Mandatory)][scriptblock]$Act,
        [Parameter(Mandatory)][scriptblock]$Assert
    )

    $arranged = $null
    $result = $null
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
        $cleanupPaths = @()
        foreach ($candidate in @($arranged, $result)) {
            if ($candidate -and ($candidate.PSObject.Properties.Name -contains 'CleanupPaths')) {
                $cleanupPaths += @($candidate.CleanupPaths)
            }
        }
        foreach ($path in $cleanupPaths) {
            if ($path) { Remove-TestPath -Path $path }
        }
    }
}

Write-Host ''
Write-Host '🔍 Running git-commit-review snapshot procedure regression suite...' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Section 2: the full snapshot tree includes an untouched tracked file and
# reflects every staged operation, while the narrower changed-path review
# scope lists only what was actually staged — and unstaged working-tree
# edits affect neither.
# ---------------------------------------------------------------------------

Test-Case -Name 'SnapshotProcedure_Should_MaterializeFullTreeAndNarrowChangedScope_When_IndexHasMixedStagedOperations' `
    -Arrange {
        $root = New-IsolatedGitRepo

        Set-RepoFile $root 'unchanged.txt' 'unchanged-original'
        Set-RepoFile $root 'modified.txt' 'modified-original'
        Set-RepoFile $root 'deleted.txt' 'deleted-original'
        Set-RepoFile $root 'old-name.txt' 'renamed-content-stable-enough-for-rename-detection'
        Set-RepoFile $root 'unstaged.txt' 'unstaged-original'
        $null = Invoke-Git -RepoRoot $root -GitArgs @('add', '.')
        $null = Invoke-Git -RepoRoot $root -GitArgs @('commit', '-q', '-m', 'baseline')

        Set-RepoFile $root 'modified.txt' 'modified-fixed-content'
        $null = Invoke-Git -RepoRoot $root -GitArgs @('add', 'modified.txt')

        Set-RepoFile $root 'added.txt' 'added-new-content'
        $null = Invoke-Git -RepoRoot $root -GitArgs @('add', 'added.txt')

        $null = Invoke-Git -RepoRoot $root -GitArgs @('rm', '-q', 'deleted.txt')
        $null = Invoke-Git -RepoRoot $root -GitArgs @('mv', 'old-name.txt', 'new-name.txt')

        # Unstaged-only edit: must not affect the snapshot tree or scope.
        Set-RepoFile $root 'unstaged.txt' 'unstaged-working-tree-only-edit'

        [pscustomobject]@{ Root = $root; CleanupPaths = @($root) }
    } `
    -Act {
        param($ctx)
        $tree = (Invoke-Git -RepoRoot $ctx.Root -GitArgs @('write-tree')).Trim()
        $lsTreePaths = @(
            (Invoke-Git -RepoRoot $ctx.Root -GitArgs @('ls-tree', '-r', '--full-tree', '--name-only', $tree)) -split "`r?`n" |
                Where-Object { $_ }
        )
        $changedScope = Invoke-Git -RepoRoot $ctx.Root -GitArgs @('diff', '--cached', '--name-status', '-M')
        $snapshot = New-Snapshot -RepoRoot $ctx.Root -Tree $tree

        [pscustomobject]@{
            Root           = $ctx.Root
            Tree           = $tree
            LsTreePaths    = $lsTreePaths
            ChangedScope   = $changedScope
            SnapshotPath   = $snapshot.SnapshotPath
            SnapshotFiles  = (Get-SnapshotFileList -SnapshotPath $snapshot.SnapshotPath)
            UnchangedBlob  = Get-GitBlobContent -RepoRoot $ctx.Root -Tree $tree -Path 'unchanged.txt'
            ModifiedBlob   = Get-GitBlobContent -RepoRoot $ctx.Root -Tree $tree -Path 'modified.txt'
            UnstagedBlob   = Get-GitBlobContent -RepoRoot $ctx.Root -Tree $tree -Path 'unstaged.txt'
            CleanupPaths   = @($snapshot.SnapshotPath, $snapshot.ArchivePath)
        }
    } `
    -Assert {
        param($ctx)
        if (-not $ctx.Tree) { throw 'expected a non-empty tree id from git write-tree.' }

        foreach ($expected in @('unchanged.txt', 'modified.txt', 'added.txt', 'new-name.txt', 'unstaged.txt')) {
            if ($ctx.LsTreePaths -notcontains $expected) {
                throw "expected '$expected' in the full snapshot tree. ls-tree: $($ctx.LsTreePaths -join ', ')"
            }
        }
        foreach ($excluded in @('deleted.txt', 'old-name.txt')) {
            if ($ctx.LsTreePaths -contains $excluded) {
                throw "expected '$excluded' excluded from the snapshot tree. ls-tree: $($ctx.LsTreePaths -join ', ')"
            }
        }

        if ($ctx.UnchangedBlob -ne 'unchanged-original') {
            throw "expected the unchanged file's original content in the full snapshot tree, got '$($ctx.UnchangedBlob)'."
        }
        if ($ctx.ModifiedBlob -ne 'modified-fixed-content') {
            throw "expected the staged modification reflected in the snapshot tree, got '$($ctx.ModifiedBlob)'."
        }
        if ($ctx.UnstagedBlob -ne 'unstaged-original') {
            throw "expected the unstaged working-tree edit excluded from the snapshot tree; got '$($ctx.UnstagedBlob)' instead of the original committed content."
        }

        if ($ctx.ChangedScope -notmatch 'M\s+modified\.txt') { throw "expected changed-path scope to list modified.txt as Modified. Scope: $($ctx.ChangedScope)" }
        if ($ctx.ChangedScope -notmatch 'A\s+added\.txt') { throw "expected changed-path scope to list added.txt as Added. Scope: $($ctx.ChangedScope)" }
        if ($ctx.ChangedScope -notmatch 'D\s+deleted\.txt') { throw "expected changed-path scope to list deleted.txt as Deleted. Scope: $($ctx.ChangedScope)" }
        if ($ctx.ChangedScope -notmatch 'R\d*\s+old-name\.txt\s+new-name\.txt') { throw "expected changed-path scope to list the old-name.txt -> new-name.txt rename. Scope: $($ctx.ChangedScope)" }
        if ($ctx.ChangedScope -match 'unchanged\.txt') { throw "changed-path scope must not include the untouched unchanged.txt. Scope: $($ctx.ChangedScope)" }
        if ($ctx.ChangedScope -match 'unstaged\.txt') { throw "changed-path scope must not include unstaged.txt, since it was never staged. Scope: $($ctx.ChangedScope)" }

        foreach ($expected in @('unchanged.txt', 'modified.txt', 'added.txt', 'new-name.txt', 'unstaged.txt')) {
            if ($ctx.SnapshotFiles -notcontains $expected) {
                throw "expected the materialized snapshot to contain '$expected'. Snapshot files: $($ctx.SnapshotFiles -join ', ')"
            }
        }
        foreach ($excluded in @('deleted.txt', 'old-name.txt')) {
            if ($ctx.SnapshotFiles -contains $excluded) {
                throw "expected the materialized snapshot to exclude '$excluded'. Snapshot files: $($ctx.SnapshotFiles -join ', ')"
            }
        }

        $snapshotUnstagedContent = Get-Content -LiteralPath (Join-Path $ctx.SnapshotPath 'unstaged.txt') -Raw
        if ($snapshotUnstagedContent -ne 'unstaged-original') {
            throw "expected the materialized snapshot's unstaged.txt to retain the original committed content, got '$snapshotUnstagedContent'."
        }
    }

# ---------------------------------------------------------------------------
# Section 7 + 9: restaging an approved fix produces a new candidate tree ID
# distinct from the original, the pre-commit guard's re-run of
# `git write-tree` matches that rematerialized tree, and re-review scope
# stays limited to the fixed file.
# ---------------------------------------------------------------------------

Test-Case -Name 'SnapshotProcedure_Should_ProduceNewTreeIdAndScopedRematerialization_When_ApprovedFixIsRestaged' `
    -Arrange {
        $root = New-IsolatedGitRepo

        Set-RepoFile $root 'candidate.txt' 'baseline-content'
        $null = Invoke-Git -RepoRoot $root -GitArgs @('add', '.')
        $null = Invoke-Git -RepoRoot $root -GitArgs @('commit', '-q', '-m', 'baseline')

        Set-RepoFile $root 'candidate.txt' 'first-draft-with-bug'
        $null = Invoke-Git -RepoRoot $root -GitArgs @('add', 'candidate.txt')
        $treeBefore = (Invoke-Git -RepoRoot $root -GitArgs @('write-tree')).Trim()

        [pscustomobject]@{ Root = $root; TreeBefore = $treeBefore; CleanupPaths = @($root) }
    } `
    -Act {
        param($ctx)
        # Approved fix: stage only the corrected content (section 7), then
        # rebind the candidate to a fresh tree and snapshot.
        Set-RepoFile $ctx.Root 'candidate.txt' 'approved-fix-content'
        $null = Invoke-Git -RepoRoot $ctx.Root -GitArgs @('add', 'candidate.txt')
        $treeAfter = (Invoke-Git -RepoRoot $ctx.Root -GitArgs @('write-tree')).Trim()

        # Section 9's immediate pre-commit guard: re-run git write-tree and
        # require it to equal the tree that was rematerialized and reviewed.
        $preCommitGuardTree = (Invoke-Git -RepoRoot $ctx.Root -GitArgs @('write-tree')).Trim()

        $changedScope = Invoke-Git -RepoRoot $ctx.Root -GitArgs @('diff', '--cached', '--name-status', '-M')
        $snapshot = New-Snapshot -RepoRoot $ctx.Root -Tree $treeAfter

        [pscustomobject]@{
            TreeBefore         = $ctx.TreeBefore
            TreeAfter          = $treeAfter
            PreCommitGuardTree = $preCommitGuardTree
            ChangedScope       = $changedScope
            SnapshotPath       = $snapshot.SnapshotPath
            CleanupPaths       = @($snapshot.SnapshotPath, $snapshot.ArchivePath)
        }
    } `
    -Assert {
        param($ctx)
        if ($ctx.TreeAfter -eq $ctx.TreeBefore) {
            throw 'expected restaging the approved fix to produce a new candidate tree ID distinct from the pre-fix draft.'
        }
        if ($ctx.PreCommitGuardTree -ne $ctx.TreeAfter) {
            throw "expected the section-9 pre-commit guard's git write-tree to equal the rematerialized fix tree ID. Guard: $($ctx.PreCommitGuardTree), fix tree: $($ctx.TreeAfter)"
        }
        if ($ctx.ChangedScope -notmatch 'M\s+candidate\.txt') {
            throw "expected the restaged fix to still scope re-review to only candidate.txt. Scope: $($ctx.ChangedScope)"
        }
        if (($ctx.ChangedScope.Trim() -split "`r?`n").Count -ne 1) {
            throw "expected exactly one changed path after restaging the approved fix. Scope: $($ctx.ChangedScope)"
        }

        $fixedContent = Get-Content -LiteralPath (Join-Path $ctx.SnapshotPath 'candidate.txt') -Raw
        if ($fixedContent -ne 'approved-fix-content') {
            throw "expected the rematerialized snapshot to contain the approved fix content, got '$fixedContent'."
        }
    }

Write-Host ''
if ($script:TestsFailed -eq 0) {
    Write-Host "✅ All $script:TestsPassed tests passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $script:TestsFailed of $($script:TestsPassed + $script:TestsFailed) tests failed." -ForegroundColor Red
exit 1
