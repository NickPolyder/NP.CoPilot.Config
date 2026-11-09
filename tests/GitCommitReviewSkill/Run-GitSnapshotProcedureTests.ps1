#Requires -Version 7.0
<#
.SYNOPSIS
    Exercises the shared snapshot helper and the skill's executable example.
.DESCRIPTION
    Real Git operations run only in registered disposable repositories with
    isolated child homes/config. Assertions inspect actual paths/types/modes/
    bytes and negative outcomes, not archive exit status or blob-only proxies.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'New-GitSnapshotFixture.ps1')
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestCandidates = [Collections.Generic.List[object]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $errorMessage = $null
    try { $null = & $Action }
    catch { $errorMessage = $_.Exception.Message }
    if (-not $errorMessage -or $errorMessage -notmatch $Pattern) {
        throw "Expected failure '$Pattern'; received '$errorMessage'."
    }
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:TestsPassed++
        Write-Host "  ✅ $Name" -ForegroundColor Green
    }
    catch {
        $script:TestsFailed++
        Write-Host "  ❌ ${Name}: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        foreach ($candidate in $script:TestCandidates) { Remove-GitReviewCandidate -Candidate $candidate }
        $script:TestCandidates.Clear()
        foreach ($root in @($script:GitFixtureContexts.Keys)) { Remove-TestPath -Path $root }
    }
}

function New-TestCandidate {
    param([string]$Root)
    $candidate = New-GitReviewCandidate -RepositoryRoot $Root
    $script:TestCandidates.Add($candidate)
    $candidate
}

function New-StagedFixture {
    param([switch]$Unborn)
    $root = New-IsolatedGitRepo
    if (-not $Unborn) {
        Set-RepoFile $root 'candidate.txt' 'base'
        $null = Invoke-Git $root @('add', '--', 'candidate.txt')
        $null = Invoke-Git $root @('commit', '-q', '-m', 'baseline')
    }
    Set-RepoFile $root 'candidate.txt' 'staged'
    $null = Invoke-Git $root @('add', '--', 'candidate.txt')
    $root
}

function New-FixtureCommit {
    param([string]$Root, [string]$Tree, [string[]]$Parents = @())
    $arguments = @('commit-tree', $Tree, '-m', 'fixture commit')
    foreach ($parent in $Parents) { $arguments += @('-p', $parent) }
    (Invoke-Git $Root $arguments).Trim()
}

function Assert-SnapshotFiles {
    param($Snapshot, [Collections.IDictionary]$ExpectedBytes)
    $actualPaths = @(Get-ChildItem -LiteralPath $Snapshot.Path -Recurse -File -Force | ForEach-Object {
        [IO.Path]::GetRelativePath($Snapshot.Path, $_.FullName).Replace('\', '/')
    } | Sort-Object -CaseSensitive)
    $expectedPaths = @($ExpectedBytes.Keys | Sort-Object -CaseSensitive)
    Assert-True (($actualPaths -join "`0") -ceq ($expectedPaths -join "`0")) 'Actual snapshot paths are not exactly the expected set.'
    foreach ($path in $expectedPaths) {
        $actual = [IO.File]::ReadAllBytes((Join-Path $Snapshot.Path $path.Replace('/', [IO.Path]::DirectorySeparatorChar)))
        Assert-True ([Convert]::ToBase64String($actual) -ceq [Convert]::ToBase64String($ExpectedBytes[$path])) "Actual bytes differ at '$path'."
        $item = Get-Item -LiteralPath (Join-Path $Snapshot.Path $path) -Force
        Assert-True (-not $item.PSIsContainer -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Wrong file type at '$path'."
        if (-not $IsWindows) {
            Assert-True ([int][IO.File]::GetUnixFileMode($item.FullName) -eq 420) "Wrong regular-file mode at '$path'."
        }
    }
}

Write-Host "`n🔍 Running shared Git snapshot regression suite..." -ForegroundColor Cyan

Test-Case 'Documented procedure preserves the exact complete staged tree and binary diff' {
    $root = New-IsolatedGitRepo
    foreach ($name in @('unchanged.txt', 'modified.txt', 'deleted.txt', 'old name.txt', 'unstaged.txt')) {
        Set-RepoFile $root $name "original:$name`n"
    }
    $null = Invoke-Git $root @('add', '.')
    $null = Invoke-Git $root @('commit', '-q', '-m', 'baseline')
    Set-RepoFile $root 'modified.txt' "staged`r`n"
    Set-RepoFile $root 'added space.txt' "added`n"
    Set-RepoFile $root 'nested\empty.txt' ''
    $binary = [byte[]]@(0, 255, 10, 13, 128, 42, 0)
    [IO.File]::WriteAllBytes((Join-Path $root 'binary.dat'), $binary)
    $null = Invoke-Git $root @('add', '.')
    $null = Invoke-Git $root @('rm', '-q', '--', 'deleted.txt')
    $null = Invoke-Git $root @('mv', '--', 'old name.txt', 'new name.txt')
    Set-RepoFile $root 'modified.txt' 'unstaged-after-stage'
    Set-RepoFile $root 'unstaged.txt' 'unstaged-only'
    $documented = Get-DocumentedSnapshot -RepoRoot $root
    $script:TestCandidates.Add($documented.Candidate)
    $expected = [ordered]@{
        'unchanged.txt' = [Text.Encoding]::UTF8.GetBytes("original:unchanged.txt`n")
        'modified.txt' = [Text.Encoding]::UTF8.GetBytes("staged`r`n")
        'added space.txt' = [Text.Encoding]::UTF8.GetBytes("added`n")
        'nested/empty.txt' = [byte[]]@()
        'new name.txt' = [Text.Encoding]::UTF8.GetBytes("original:old name.txt`n")
        'unstaged.txt' = [Text.Encoding]::UTF8.GetBytes("original:unstaged.txt`n")
        'binary.dat' = $binary
    }
    Assert-SnapshotFiles $documented.Snapshot $expected
    $expectedBase = @{}
    foreach ($name in @('modified.txt', 'deleted.txt', 'old name.txt')) {
        $expectedBase[$name] = [Text.Encoding]::UTF8.GetBytes("original:$name`n")
    }
    Assert-SnapshotFiles $documented.BaseSnapshot $expectedBase
    Assert-True $documented.BaseSnapshot.IsPartial 'The normal procedure copied the full base tree.'
    Assert-True ($documented.BaseSnapshot.Role -ceq 'base' -and $documented.Snapshot.Role -ceq 'candidate') 'Snapshot roles are ambiguous.'
    Assert-True ($documented.BaseSnapshot.Tree -ceq (Invoke-Git $root @('rev-parse', "$($documented.Candidate.State.Base)^{tree}")).Trim()) 'Readable base context has the wrong tree identity.'
    $scope = @($documented.Candidate.ChangedPaths | Sort-Object -CaseSensitive)
    $expectedScope = @('modified.txt', 'deleted.txt', 'old name.txt', 'new name.txt', 'added space.txt', 'nested/empty.txt', 'binary.dat' | Sort-Object -CaseSensitive)
    Assert-True (($scope -join "`0") -ceq ($expectedScope -join "`0")) 'Changed scope omitted an operation or included an unstaged-only file.'
    $diff = [Text.Encoding]::UTF8.GetString($documented.Candidate.DiffBytes)
    Assert-True ($diff.Contains('GIT binary patch') -and $diff.Contains('rename from old name.txt')) 'Captured diff lost binary or rename information.'
}

Test-Case 'Unborn reviewer base context is explicitly empty, not candidate or worktree content' {
    $root = New-StagedFixture -Unborn
    $documented = Get-DocumentedSnapshot -RepoRoot $root
    $script:TestCandidates.Add($documented.Candidate)
    Assert-True ($documented.BaseSnapshot.Manifest.Count -eq 0 -and $documented.BaseSnapshot.Tree -ceq $documented.Candidate.State.Base) 'Unborn base manifest/identity is not the empty tree.'
    Assert-True (@(Get-ChildItem -LiteralPath $documented.BaseSnapshot.Path -Force).Count -eq 0) 'Unborn base contains substituted current files.'
    Assert-SnapshotFiles $documented.Snapshot @{ 'candidate.txt' = [Text.Encoding]::UTF8.GetBytes('staged') }
}

Test-Case 'Base context cannot be substituted for candidate validation even when its tree is identical' {
    $root = New-StagedFixture
    $null = Invoke-Git $root @('commit', '-q', '-m', 'same-tree baseline')
    $candidate = New-GitReviewCandidate -RepositoryRoot $root -AllowEmpty
    $script:TestCandidates.Add($candidate)
    $base = New-GitTreeSnapshot -Candidate $candidate -Base
    Assert-True ($base.Tree -ceq $candidate.Tree) 'The role counterexample must use identical trees.'
    Assert-Throws {
        Invoke-GitSnapshotCheck -Snapshot $base -Name 'wrong target' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-Command', "[IO.File]::WriteAllText('unexpected.txt', 'must not run')")
    } 'Validation requires the captured candidate snapshot; base context is read-only'
    Assert-GitSnapshotIntegrity -Snapshot $base -Exact
    Assert-True ($base.Checks.Count -eq 0) 'Base context was recorded as candidate validation evidence.'
}

Test-Case 'Altered readable base context invalidates intake evidence permanently' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $base = New-GitTreeSnapshot -Candidate $candidate -Base
    $path = Join-Path $base.Path 'candidate.txt'
    [IO.File]::WriteAllText($path, 'current-file substitute')
    Assert-Throws { Assert-GitSnapshotIntegrity -Snapshot $base -Exact } 'changed bytes'
    [IO.File]::WriteAllText($path, 'base')
    Assert-Throws { Assert-GitSnapshotIntegrity -Snapshot $base -Exact } 'already invalidated'
}

Test-Case 'Export attributes and failing checkout filters cannot omit or rewrite inputs' {
    $root = New-StagedFixture
    $attributes = "ignored.txt export-ignore`nsubstituted.txt export-subst`nfiltered.txt filter=fixture ident text eol=crlf`n"
    Set-RepoFile $root '.gitattributes' $attributes
    Set-RepoFile $root 'ignored.txt' 'must remain'
    Set-RepoFile $root 'substituted.txt' '$Format:%H$'
    $null = Invoke-Git $root @('add', '.')
    $filtered = [Text.Encoding]::UTF8.GetBytes("raw`n`$Id`$`n")
    $null = Add-FixtureIndexBlob -RepoRoot $root -GitPath 'filtered.txt' -Bytes $filtered
    $null = Invoke-Git $root @('config', '--local', 'filter.fixture.smudge', 'missing-smudge-command')
    $null = Invoke-Git $root @('config', '--local', 'filter.fixture.required', 'true')
    Set-RepoFile $root '.gitattributes' '* export-ignore'
    $candidate = New-TestCandidate $root
    $snapshot = New-GitTreeSnapshot $candidate
    Assert-SnapshotFiles $snapshot ([ordered]@{
        '.gitattributes' = [Text.Encoding]::UTF8.GetBytes($attributes)
        'candidate.txt' = [Text.Encoding]::UTF8.GetBytes('staged')
        'ignored.txt' = [Text.Encoding]::UTF8.GetBytes('must remain')
        'substituted.txt' = [Text.Encoding]::UTF8.GetBytes('$Format:%H$')
        'filtered.txt' = $filtered
    })
}

foreach ($mutation in @('bytes', 'missing', 'extra-file', 'extra-directory', 'type')) {
    Test-Case "Exact integrity gate rejects $mutation mutation" {
        $candidate = New-TestCandidate (New-StagedFixture)
        $snapshot = New-GitTreeSnapshot $candidate
        $path = Join-Path $snapshot.Path 'candidate.txt'
        switch ($mutation) {
            'bytes' { [IO.File]::WriteAllText($path, 'tampered') }
            'missing' { Remove-Item -LiteralPath $path }
            'extra-file' { [IO.File]::WriteAllText((Join-Path $snapshot.Path '.unexpected'), 'extra') }
            'extra-directory' { $null = New-Item -ItemType Directory -Path (Join-Path $snapshot.Path 'unexpected') }
            'type' { Remove-Item -LiteralPath $path; $null = New-Item -ItemType Directory -Path $path }
        }
        Assert-Throws { Assert-GitSnapshotIntegrity $snapshot -Exact } '(changed bytes|missing tracked|unexpected path|changed file type)'
        Assert-True $snapshot.Invalidated 'Integrity failure did not latch invalid evidence.'
    }
}

foreach ($phase in @('preflight', 'build', 'lint', 'targeted tests', 'final suite')) {
    Test-Case "Successful $phase cannot validate mutated tracked inputs or restored bytes" {
        $candidate = New-TestCandidate (New-StagedFixture)
        $snapshot = New-GitTreeSnapshot $candidate
        Assert-Throws {
            Invoke-GitSnapshotCheck $snapshot -Name $phase -FilePath 'pwsh' `
                -ArgumentList @('-NoProfile', '-Command', "[IO.File]::WriteAllText('candidate.txt', 'tested-mutated'); exit 0")
        } 'changed bytes'
        [IO.File]::WriteAllText((Join-Path $snapshot.Path 'candidate.txt'), 'staged')
        Assert-Throws { Assert-GitSnapshotIntegrity $snapshot } 'already invalidated.*Restoring bytes cannot restore'
        Assert-True ($snapshot.Checks.Count -eq 0) 'Mutated bytes were recorded as passing evidence.'
        $fresh = New-GitTreeSnapshot $candidate
        Assert-GitSnapshotIntegrity $fresh -Exact
        Assert-True ($fresh.Checks.Count -eq 0) 'New snapshot inherited invalid test evidence.'
    }
}

Test-Case 'Ordinary untracked build output is allowed without touching tracked bytes' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $snapshot = New-GitTreeSnapshot $candidate
    $result = Invoke-GitSnapshotCheck $snapshot -Name 'build output' -FilePath 'pwsh' -ArgumentList @(
        '-NoProfile', '-Command', "[IO.Directory]::CreateDirectory('out') > `$null; [IO.File]::WriteAllText((Join-Path 'out' 'result.txt'), 'output')"
    )
    Assert-True ($result.ExitCode -eq 0 -and $snapshot.Checks.Count -eq 1) 'Untracked-output positive control did not pass.'
    Assert-GitSnapshotIntegrity $snapshot
}

Test-Case 'Staged-only validation catches dependencies supplied only by untracked worktree files' {
    $root = New-StagedFixture
    Set-RepoFile $root 'check.ps1' 'if (-not (Test-Path -LiteralPath dependency.txt)) { throw "Missing dependency" }'
    $null = Invoke-Git $root @('add', '--', 'check.ps1')
    Set-RepoFile $root 'dependency.txt' 'worktree dependency'
    $worktree = Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$root] -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-File', 'check.ps1') -WorkingDirectory $root
    Assert-True ($worktree.ExitCode -eq 0) 'The worktree positive control did not pass.'
    $snapshot = New-GitTreeSnapshot (New-TestCandidate $root)
    Assert-Throws {
        Invoke-GitSnapshotCheck $snapshot -Name 'dependency check' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', 'check.ps1') -RequiredPaths @('check.ps1')
    } 'Missing dependency'
    $null = Invoke-Git $root @('add', '--', 'dependency.txt')
    $fixed = New-GitTreeSnapshot (New-TestCandidate $root)
    $null = Invoke-GitSnapshotCheck $fixed -Name 'dependency check' -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-File', 'check.ps1') -RequiredPaths @('check.ps1', 'dependency.txt')
}

Test-Case 'Staged bytes catch a working-file fix hidden from ordinary status checks' {
    $root = New-StagedFixture
    Set-RepoFile $root 'check.ps1' 'if ([IO.File]::ReadAllText("candidate.txt") -cne "fixed") { throw "Fix absent from candidate" }'
    $null = Invoke-Git $root @('add', '--', 'check.ps1')
    $null = Invoke-Git $root @('update-index', '--assume-unchanged', '--', 'candidate.txt')
    Set-RepoFile $root 'candidate.txt' 'fixed'
    Assert-True ([string]::IsNullOrWhiteSpace((Invoke-Git $root @('diff', '--', 'candidate.txt')))) 'The status-metadata counterexample was not established.'
    $worktree = Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$root] -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-File', 'check.ps1') -WorkingDirectory $root
    Assert-True ($worktree.ExitCode -eq 0) 'The worktree positive control did not pass.'
    $snapshot = New-GitTreeSnapshot (New-TestCandidate $root)
    Assert-Throws {
        Invoke-GitSnapshotCheck $snapshot -Name 'fixture fix' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', 'check.ps1')
    } 'Fix absent from candidate'
    $null = Invoke-Git $root @('update-index', '--no-assume-unchanged', '--', 'candidate.txt')
    $null = Invoke-Git $root @('add', '--', 'candidate.txt')
    $fixed = New-GitTreeSnapshot (New-TestCandidate $root)
    $null = Invoke-GitSnapshotCheck $fixed -Name 'fixture fix' -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-File', 'check.ps1')
}

Test-Case 'Selected base context includes old changed files without copying unrelated tracked content' {
    $root = New-StagedFixture
    Set-RepoFile $root 'unrelated.txt' 'large unrelated context'
    $null = Invoke-Git $root @('add', '--', 'unrelated.txt')
    $null = Invoke-Git $root @('commit', '-q', '-m', 'unrelated base context')
    Set-RepoFile $root 'candidate.txt' 'changed'
    Set-RepoFile $root 'added.txt' 'new file'
    $null = Invoke-Git $root @('add', '--all')
    $candidate = New-TestCandidate $root
    $base = New-GitTreeSnapshot $candidate -Base -Paths $candidate.ChangedPaths
    Assert-SnapshotFiles $base @{ 'candidate.txt' = [Text.Encoding]::UTF8.GetBytes('staged') }
    Assert-True ($base.IsPartial -and $base.ScopePaths -ccontains 'added.txt') 'Selected scope was not recorded, including an absent-at-base addition.'
    $additional = New-GitTreeSnapshot $candidate -Base -Paths @('unrelated.txt')
    Assert-SnapshotFiles $additional @{ 'unrelated.txt' = [Text.Encoding]::UTF8.GetBytes('large unrelated context') }
    Assert-Throws { New-GitTreeSnapshot $candidate -Paths @('candidate.txt') } 'candidate validation requires the complete tree'
    Assert-Throws { New-GitTreeSnapshot $candidate -Base -Paths @('../outside') } 'Unsupported or unsafe Git path'
    $empty = New-GitTreeSnapshot $candidate -Base -Paths @()
    Assert-True ($empty.IsPartial -and $empty.Manifest.Count -eq 0) 'Empty selection copied the full base.'
}

Test-Case 'Unchanged approval waits retain the snapshot and successful checks without rerunning them' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $snapshot = New-GitTreeSnapshot $candidate
    $path = $snapshot.Path
    $null = Invoke-GitSnapshotCheck $snapshot -Name 'single execution' -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-Command', '[IO.File]::AppendAllText("execution-count.txt", "1")')
    Assert-GitSnapshotIntegrity $snapshot
    Assert-GitCandidateCurrent $candidate
    $refresh = Update-GitReviewCandidate -Candidate $candidate -Snapshot $snapshot
    Assert-True (-not $refresh.StateChanged -and $snapshot.Path -ceq $path -and $snapshot.Checks.Count -eq 1) 'An unchanged candidate lost its snapshot or evidence.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $path 'execution-count.txt')) -ceq '1') 'Validation was unnecessarily repeated.'
    Assert-True (@(Get-ChildItem -LiteralPath $candidate.Context.Root -Directory -Filter 'snapshot-*').Count -eq 1) 'Approval retention created another snapshot.'
}

Test-Case 'State-only refresh retains bytes and original check identity but requires a new approval tuple' {
    $root = New-StagedFixture
    $candidate = New-TestCandidate $root
    $snapshot = New-GitTreeSnapshot $candidate
    $path = $snapshot.Path
    $null = Invoke-GitSnapshotCheck $snapshot -Name 'original check' -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'exit 0')
    $oldState = $candidate.State
    $other = New-FixtureCommit $root (Invoke-Git $root @('rev-parse', 'HEAD^{tree}')).Trim() $candidate.State.Parents
    $null = Invoke-Git $root @('update-ref', 'HEAD', $other)
    Assert-Throws { Assert-GitCandidateCurrent $candidate } 'Head changed'
    $refresh = Update-GitReviewCandidate -Candidate $candidate -Snapshot $snapshot
    Assert-True ($refresh.StateChanged -and $refresh.PreviousState.Head -ceq $oldState.Head -and $refresh.State.Head -ceq $other) 'State drift was not explicitly exposed.'
    Assert-True ($snapshot.Path -ceq $path -and $snapshot.Checks[0].CandidateState.Head -ceq $oldState.Head) 'Snapshot was recopied or old evidence relabeled as a new execution.'
    Assert-GitCandidateCurrent $candidate
    Set-RepoFile $root 'candidate.txt' 'new candidate'
    $null = Invoke-Git $root @('add', '--', 'candidate.txt')
    Assert-Throws { Update-GitReviewCandidate -Candidate $candidate -Snapshot $snapshot } 'index tree changed; create a new candidate snapshot'
    Assert-True ($candidate.State.Head -ceq $other) 'Failed content refresh altered the retained state.'
}

Test-Case 'State refresh rejects tampered snapshots rather than transferring evidence' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $snapshot = New-GitTreeSnapshot $candidate
    [IO.File]::WriteAllText((Join-Path $snapshot.Path 'candidate.txt'), 'tampered')
    Assert-Throws { Update-GitReviewCandidate -Candidate $candidate -Snapshot $snapshot } 'changed bytes'
}

Test-Case 'Native check failures invalidate evidence even when inputs are unchanged' {
    $snapshot = New-GitTreeSnapshot (New-TestCandidate (New-StagedFixture))
    Assert-Throws { Invoke-GitSnapshotCheck $snapshot -Name 'failure' -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'exit 17') } 'failed with exit 17'
    Assert-True $snapshot.Invalidated 'Failed validation was not invalidated.'
}

Test-Case 'Linked outputs are rejected without following another owned fixture' {
    $snapshot = New-GitTreeSnapshot (New-TestCandidate (New-StagedFixture))
    $other = New-StagedFixture
    $path = Join-Path $other 'candidate.txt'
    $before = (Get-FileHash -LiteralPath $path).Hash
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    $null = New-Item -ItemType $linkType -Path (Join-Path $snapshot.Path 'linked-output') -Target $other
    Assert-Throws { Assert-GitSnapshotIntegrity $snapshot } 'linked path.*not an ordinary build output'
    Assert-True ((Get-FileHash -LiteralPath $path).Hash -ceq $before) 'A linked fixture target was changed.'
}

Test-Case 'Target capabilities do not assume a configuration validator in other projects' {
    $root = New-StagedFixture
    Set-RepoFile $root '.github\copilot-instructions.md' '# Downstream instructions'
    Set-RepoFile $root 'check.ps1' 'exit 0'
    $null = Invoke-Git $root @('add', '.')
    $snapshot = New-GitTreeSnapshot (New-TestCandidate $root)
    $null = Invoke-GitSnapshotCheck $snapshot -Name 'declared downstream check' -FilePath 'pwsh' `
        -ArgumentList @('-NoProfile', '-File', 'check.ps1') -RequiredPaths @('check.ps1')
    Assert-Throws {
        Invoke-GitSnapshotCheck $snapshot -Name 'missing declared check' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', 'scripts\Validate-Config.ps1') -RequiredPaths @('scripts\Validate-Config.ps1')
    } 'Declared required validation input.*missing from the candidate tree'
}

Test-Case 'Restaging a fix invalidates the old tree and binds a new snapshot' {
    $root = New-StagedFixture
    $old = New-TestCandidate $root
    Set-RepoFile $root 'candidate.txt' 'fixed'
    $null = Invoke-Git $root @('add', '--', 'candidate.txt')
    Assert-Throws { Assert-GitCandidateCurrent $old } 'index tree changed'
    $new = New-TestCandidate $root
    Assert-True ($new.Tree -cne $old.Tree) 'Restaging failed to produce a new tree.'
    $snapshot = New-GitTreeSnapshot $new
    Assert-SnapshotFiles $snapshot @{ 'candidate.txt' = [Text.Encoding]::UTF8.GetBytes('fixed') }
}

foreach ($drift in @('same-ref base', 'destination branch', 'detached state', 'unborn transition', 'ordered merge parents')) {
    Test-Case "Pre-commit tuple gate rejects $drift despite an unchanged index tree" {
        $root = New-StagedFixture -Unborn:($drift -eq 'unborn transition')
        if ($drift -eq 'ordered merge parents') {
            $baseTree = (Invoke-Git $root @('rev-parse', 'HEAD^{tree}')).Trim()
            $side1 = New-FixtureCommit $root $baseTree
            $side2 = New-FixtureCommit $root $baseTree @($side1)
            [IO.File]::WriteAllText((Join-Path $root '.git\MERGE_HEAD'), "$side1`n$side2`n")
        }
        $candidate = New-TestCandidate $root
        switch ($drift) {
            'same-ref base' {
                $other = New-FixtureCommit $root $candidate.Tree $candidate.State.Parents
                $null = Invoke-Git $root @('update-ref', 'HEAD', $other)
            }
            'destination branch' {
                $null = Invoke-Git $root @('update-ref', 'refs/heads/other', $candidate.State.Head)
                $null = Invoke-Git $root @('symbolic-ref', 'HEAD', 'refs/heads/other')
            }
            'detached state' { $null = Invoke-Git $root @('update-ref', '--no-deref', 'HEAD', $candidate.State.Head) }
            'unborn transition' {
                $other = New-FixtureCommit $root $candidate.Tree
                $null = Invoke-Git $root @('update-ref', 'HEAD', $other)
            }
            'ordered merge parents' { [IO.File]::WriteAllText((Join-Path $root '.git\MERGE_HEAD'), "$side2`n$side1`n") }
        }
        Assert-True ((Invoke-Git $root @('write-tree')).Trim() -ceq $candidate.Tree) 'The counterexample unexpectedly changed the index tree.'
        Assert-Throws { Assert-GitCandidateCurrent $candidate } 'Candidate approval invalidated'
    }
}

foreach ($kind in @('ordinary', 'unborn', 'detached', 'merge')) {
    Test-Case "Pre/post gates accept the approved $kind commit tuple" {
        $root = New-StagedFixture -Unborn:($kind -eq 'unborn')
        if ($kind -eq 'detached') {
            $head = (Invoke-Git $root @('rev-parse', 'HEAD')).Trim()
            $null = Invoke-Git $root @('update-ref', '--no-deref', 'HEAD', $head)
        }
        if ($kind -eq 'merge') {
            $side = New-FixtureCommit $root (Invoke-Git $root @('rev-parse', 'HEAD^{tree}')).Trim()
            [IO.File]::WriteAllText((Join-Path $root '.git\MERGE_HEAD'), "$side`n")
        }
        $candidate = New-TestCandidate $root
        Assert-GitCandidateCurrent $candidate
        $commit = New-FixtureCommit $root $candidate.Tree $candidate.State.Parents
        $null = Invoke-Git $root @('update-ref', 'HEAD', $commit)
        if ($kind -eq 'merge') { Remove-Item -LiteralPath (Join-Path $root '.git\MERGE_HEAD') }
        Assert-GitCandidateCommit $candidate -CommitId $commit
    }
}

foreach ($mismatch in @('tree', 'parents', 'destination', 'ref-state')) {
    Test-Case "Post-commit gate rejects mismatched $mismatch without automatic repair" {
        $root = New-StagedFixture
        $candidate = New-TestCandidate $root
        $tree = if ($mismatch -eq 'tree') { (Invoke-Git $root @('rev-parse', 'HEAD^{tree}')).Trim() } else { $candidate.Tree }
        $parents = if ($mismatch -eq 'parents') { @() } else { $candidate.State.Parents }
        $commit = New-FixtureCommit $root $tree $parents
        $null = Invoke-Git $root @('update-ref', 'HEAD', $commit)
        if ($mismatch -eq 'destination') {
            $null = Invoke-Git $root @('update-ref', 'refs/heads/other', $commit)
            $null = Invoke-Git $root @('symbolic-ref', 'HEAD', 'refs/heads/other')
        }
        if ($mismatch -eq 'ref-state') { $null = Invoke-Git $root @('update-ref', '--no-deref', 'HEAD', $commit) }
        Assert-Throws { Assert-GitCandidateCommit $candidate -CommitId $commit } 'differs.*Stop delivery; do not automatically amend'
        Assert-True ((Invoke-Git $root @('rev-parse', 'HEAD')).Trim() -ceq $commit) 'The post gate rewrote the commit.'
    }
}

Test-Case 'Missing and corrupt explicit indexes fail closed, not as empty candidates' {
    $root = New-StagedFixture
    $index = Join-Path $script:GitFixtureContexts[$root].Root 'invalid.index'
    Assert-Throws { New-GitReviewCandidate -RepositoryRoot $root -IndexPath $index -AllowEmpty } 'explicitly selected candidate index is missing'
    [IO.File]::WriteAllText($index, 'not a Git index')
    Assert-Throws { New-GitReviewCandidate -RepositoryRoot $root -IndexPath $index -AllowEmpty } 'failed with exit.*index'
}

Test-Case 'Native discovery failure cannot become a successful empty skip' {
    $root = New-IsolatedGitRepo
    Remove-Item -LiteralPath (Join-Path $root '.git') -Recurse -Force
    Assert-Throws { New-GitReviewCandidate -RepositoryRoot $root -AllowEmpty } 'failed with exit'
}

Test-Case 'Missing blob materialization fails explicitly' {
    $root = New-StagedFixture -Unborn
    $candidate = New-TestCandidate $root
    $blob = (Invoke-Git $root @('rev-parse', "$($candidate.Tree):candidate.txt")).Trim()
    $objectPath = Join-Path $root (Join-Path '.git\objects' (Join-Path $blob.Substring(0, 2) $blob.Substring(2)))
    Remove-Item -LiteralPath $objectPath -Force
    Assert-Throws { New-GitTreeSnapshot $candidate } '(failed with exit|missing|invalid object)'
}

Test-Case 'Batch materialization handles pipe backpressure, duplicate blobs, empty files, and large binary payloads' {
    $root = New-IsolatedGitRepo
    $expected = @{}
    foreach ($index in 1..2048) {
        $name = "files/$index.txt"
        Set-RepoFile $root $name "repeated blob`n"
        $expected[$name] = [Text.Encoding]::UTF8.GetBytes("repeated blob`n")
    }
    Set-RepoFile $root 'empty.txt' ''
    $expected['empty.txt'] = [byte[]]@()
    $bytes = [byte[]]::new(2MB + 17)
    [Random]::new(42).NextBytes($bytes)
    [IO.File]::WriteAllBytes((Join-Path $root 'binary.dat'), $bytes)
    $expected['binary.dat'] = $bytes
    $null = Invoke-Git $root @('add', '--all')
    $candidate = New-TestCandidate $root
    $snapshot = New-GitTreeSnapshot $candidate
    Assert-SnapshotFiles $snapshot $expected
}

$batchOid = 'a' * 40
foreach ($response in @(
    @{ Name = 'missing object'; Bytes = "$batchOid missing`n"; Pattern = 'Invalid Git batch response' }
    @{ Name = 'wrong identity'; Bytes = "$('b' * 40) blob 0`n`n"; Pattern = 'Invalid Git batch response' }
    @{ Name = 'wrong object type'; Bytes = "$batchOid tree 0`n`n"; Pattern = 'Invalid Git batch response' }
    @{ Name = 'overflowed length'; Bytes = "$batchOid blob 9223372036854775808`n"; Pattern = 'Invalid Git batch response' }
    @{ Name = 'truncated header'; Bytes = "$batchOid blob 0"; Pattern = 'truncated Git batch header' }
    @{ Name = 'truncated prefix'; Bytes = "$batchOid blob 10`nshort"; Pattern = 'Truncated Git batch blob' }
    @{ Name = 'truncated body'; Bytes = "$batchOid blob 1000`n$('x' * 300)"; Pattern = 'Truncated Git batch blob' }
    @{ Name = 'missing separator'; Bytes = "$batchOid blob 0`n"; Pattern = 'missing Git batch separator' }
    @{ Name = 'wrong separator'; Bytes = "$batchOid blob 0`nx"; Pattern = 'missing Git batch separator' }
)) {
    Test-Case "Batch parser rejects $($response.Name)" {
        $root = New-IsolatedGitRepo
        $stream = [IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes($response.Bytes))
        try {
            $entry = [pscustomobject]@{ Path = 'blob.dat'; ObjectId = $batchOid }
            $destination = Join-Path $root 'blob.dat'
            Assert-Throws {
                & (Get-Module GitSnapshot) {
                    param($stream, $entry, $destination)
                    Copy-GitBatchBlob -Stream $stream -Entry $entry -Destination $destination -Buffer ([byte[]]::new(65536))
                } $stream $entry $destination
            } $response.Pattern
        }
        finally { $stream.Dispose() }
    }
}

Test-Case 'A failed streaming consumer terminates its native child' {
    $root = New-IsolatedGitRepo
    $context = $script:GitFixtureContexts[$root]
    $pidPath = Join-Path $root 'child.pid'
    $command = '[IO.File]::WriteAllText($env:FIXTURE_PID, [string]$PID); [Console]::WriteLine("ready"); Start-Sleep -Seconds 120'
    Assert-Throws {
        Invoke-IsolatedProcess -Context $context -FilePath 'pwsh' -WorkingDirectory $root `
            -ArgumentList @('-NoProfile', '-Command', $command) -Environment @{ FIXTURE_PID = $pidPath } `
            -StandardOutputHandler {
                param($stream)
                $null = $stream.ReadByte()
                throw 'Fixture consumer failed'
            }
    } 'Fixture consumer failed'
    $childId = [int][IO.File]::ReadAllText($pidPath)
    Assert-Throws { [Diagnostics.Process]::GetProcessById($childId) } 'not running|not found|does not exist'
}

$snapshotRuntimes = @('pwsh')
if ($IsWindows) { $snapshotRuntimes += 'powershell.exe' }
foreach ($runtime in $snapshotRuntimes) {
    Test-Case "Process deadlines bound reads, input backpressure, and exit waits under $runtime" {
        $root = New-IsolatedGitRepo
        $context = $script:GitFixtureContexts[$root]
        $command = @'
$ErrorActionPreference = 'Stop'
Import-Module $env:FIXTURE_PROCESS_HELPER -ErrorAction Stop
$context = New-IsolatedProcessContext
try {
    foreach ($mode in @('read', 'async-read', 'trickle', 'write', 'flush', 'exit')) {
        $pidPath = Join-Path $env:FIXTURE_REPO "$mode.pid"
        $arguments = @{
            Context = $context
            FilePath = $env:FIXTURE_RUNTIME
            WorkingDirectory = $env:FIXTURE_REPO
            ArgumentList = @('-NoProfile', '-Command', '[IO.File]::WriteAllText($env:FIXTURE_PID, [string]$PID); Start-Sleep -Seconds 60')
            Environment = @{ FIXTURE_PID = $pidPath }
            TimeoutSeconds = 3
            AllowFailure = $true
        }
        if ($mode -eq 'read') {
            $arguments.StandardOutputHandler = { param($stream) $null = $stream.ReadByte() }
        }
        if ($mode -eq 'async-read') {
            $arguments.StandardOutputHandler = {
                param($stream)
                $null = $stream.ReadAsync([byte[]]::new(1), 0, 1).GetAwaiter().GetResult()
            }
        }
        if ($mode -eq 'trickle') {
            $arguments.ArgumentList = @('-NoProfile', '-Command', '[IO.File]::WriteAllText($env:FIXTURE_PID, [string]$PID); foreach ($i in 1..120) { [Console]::Write("."); [Threading.Thread]::Sleep(500) }')
            $arguments.StandardOutputHandler = { param($stream) while ($stream.ReadByte() -ne -1) { } }
        }
        if ($mode -in @('write', 'flush')) { $arguments.InputBytes = [byte[]]::new(1MB) }
        if ($mode -eq 'flush') { $arguments.StandardOutputHandler = { param($stream) } }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $failure = $null
        try { $null = Invoke-IsolatedProcess @arguments }
        catch { $failure = $_.Exception.Message }
        if ($failure -notmatch 'timed out after 3 seconds') { throw "Wrong $mode timeout outcome: $failure" }
        if ($clock.Elapsed.TotalSeconds -gt 12) { throw "Unbounded $mode timeout cleanup." }
        $childId = [int][IO.File]::ReadAllText($pidPath)
        $child = $null
        try { $child = [Diagnostics.Process]::GetProcessById($childId) }
        catch [ArgumentException] { }
        if ($child) {
            try { if (-not $child.HasExited) { throw "Timed-out $mode child is still running." } }
            finally { $child.Dispose() }
        }
    }
    $result = Invoke-IsolatedProcess -Context $context -FilePath $env:FIXTURE_RUNTIME -WorkingDirectory $env:FIXTURE_REPO `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 2; [Console]::Write("completed")') -TimeoutSeconds 10
    if ($result.Stdout -cne 'completed') { throw 'Explicit longer deadline did not permit completion.' }
    $result = Invoke-IsolatedProcess -Context $context -FilePath $env:FIXTURE_RUNTIME -WorkingDirectory $env:FIXTURE_REPO `
        -ArgumentList @('-NoProfile', '-Command', '$bytes = [byte[]]@(1, 0, 255, 42); [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)') `
        -StandardOutputHandler {
            param($stream)
            if ($stream.ReadByte() -ne 1) { throw 'Incorrect response prefix.' }
        }
    if ([Convert]::ToBase64String($result.Bytes) -cne [Convert]::ToBase64String([byte[]]@(0, 255, 42))) {
        throw 'Buffered trailing stdout bytes were lost or changed.'
    }
}
finally { Remove-IsolatedProcessContext $context }
'@
        $executable = (Get-Command $runtime -CommandType Application -ErrorAction Stop).Source
        $runtimeArguments = @('-NoProfile')
        if ($runtime -eq 'powershell.exe') { $runtimeArguments += @('-ExecutionPolicy', 'Bypass') }
        $runtimeArguments += @('-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
        $result = Invoke-IsolatedProcess -Context $context -FilePath $executable -WorkingDirectory $root `
            -ArgumentList $runtimeArguments -Environment @{
                FIXTURE_PROCESS_HELPER = Join-Path $script:SnapshotRepoRoot 'scripts\IsolatedProcess.psm1'
                FIXTURE_REPO = $root
                FIXTURE_RUNTIME = $executable
                PSModulePath = $null
            } -AllowFailure
        Assert-True ($result.ExitCode -eq 0) $result.Output
    }

    Test-Case "Streaming requests flush short input and buffered tails under $runtime" {
        $root = New-IsolatedGitRepo
        $blob = 'x' * 4097
        $oid = Add-FixtureIndexBlob $root 'blob.dat' ([Text.Encoding]::ASCII.GetBytes($blob))
        $context = $script:GitFixtureContexts[$root]
        $command = @'
$ErrorActionPreference = 'Stop'
Import-Module $env:FIXTURE_PROCESS_HELPER -ErrorAction Stop
$context = New-IsolatedProcessContext
try {
    foreach ($count in @(1, 25, 2049)) {
        $requests = [Text.Encoding]::ASCII.GetBytes(("$($env:FIXTURE_OID)`n" * $count))
        $expected = [Text.Encoding]::ASCII.GetBytes(("$($env:FIXTURE_OID) blob 4097`n" + ('x' * 4097) + "`n") * $count)
        $received = [IO.MemoryStream]::new()
        try {
            $result = Invoke-IsolatedProcess -Context $context -FilePath 'git' -WorkingDirectory $env:FIXTURE_REPO `
                -ArgumentList @('cat-file', '--batch') -InputBytes $requests -StandardOutputHandler {
                    param($stream)
                    $buffer = [byte[]]::new(65536)
                    while ($received.Length -lt $expected.Length) {
                        $read = $stream.ReadAsync($buffer, 0, [int][Math]::Min($buffer.Length, $expected.Length - $received.Length))
                        if (-not $read.Wait(10000)) { throw "Timed out waiting for $count flushed batch requests." }
                        $length = $read.GetAwaiter().GetResult()
                        if ($length -eq 0) { throw 'Truncated batch response.' }
                        $received.Write($buffer, 0, $length)
                    }
                }
            if ($result.Bytes.Length -ne 0 -or
                [Convert]::ToBase64String($received.ToArray()) -cne [Convert]::ToBase64String($expected)) {
                throw "Incorrect batch bytes for $count requests."
            }
        }
        finally { $received.Dispose() }
    }
}
finally { Remove-IsolatedProcessContext $context }
'@
        $executable = (Get-Command $runtime -CommandType Application -ErrorAction Stop).Source
        $runtimeArguments = @('-NoProfile')
        if ($runtime -eq 'powershell.exe') { $runtimeArguments += @('-ExecutionPolicy', 'Bypass') }
        $runtimeArguments += @('-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
        $result = Invoke-IsolatedProcess -Context $context -FilePath $executable -WorkingDirectory $root `
            -ArgumentList $runtimeArguments -Environment @{
                FIXTURE_PROCESS_HELPER = Join-Path $script:SnapshotRepoRoot 'scripts\IsolatedProcess.psm1'
                FIXTURE_REPO = $root
                FIXTURE_OID = $oid
                PSModulePath = $null
            } -AllowFailure
        Assert-True ($result.ExitCode -eq 0) $result.Output
    }

    Test-Case "Snapshot capture, streaming, checks, and native arguments work under $runtime" {
        $root = New-IsolatedGitRepo -DirectoryName "repo with spaces $([char]0x03BB)"
        foreach ($index in 1..2048) { Set-RepoFile $root "files\$index.txt" 'base' }
        Set-RepoFile $root 'empty.txt' ''
        $null = Invoke-Git $root @('add', '--all')
        $null = Invoke-Git $root @('commit', '-q', '-m', 'baseline')
        $bytes = [byte[]]::new(1MB + 17)
        [Random]::new(42).NextBytes($bytes)
        [IO.File]::WriteAllBytes((Join-Path $root 'binary.dat'), $bytes)
        Set-RepoFile $root 'files\1.txt' 'staged'
        $null = Invoke-Git $root @('add', '--all')
        $context = $script:GitFixtureContexts[$root]
        $command = @'
$ErrorActionPreference = 'Stop'
Import-Module $env:FIXTURE_HELPER -ErrorAction Stop
Import-Module $env:FIXTURE_PROCESS_HELPER -ErrorAction Stop
$candidate = $null
$probe = New-IsolatedProcessContext
try {
    $values = @('', 'space name', '"quoted"', 'slash\"quote', 'trailing space\', [string][char]0x03BB)
    foreach ($value in $values) {
        $null = Invoke-IsolatedProcess -Context $probe -FilePath 'git' -WorkingDirectory $env:FIXTURE_REPO `
            -ArgumentList @('-C', $env:FIXTURE_REPO, 'config', '--local', 'fixture.argument', $value)
        $read = Invoke-IsolatedProcess -Context $probe -FilePath 'git' -WorkingDirectory $env:FIXTURE_REPO `
            -ArgumentList @('-C', $env:FIXTURE_REPO, 'config', '--local', '--get', 'fixture.argument')
        if ($read.Stdout.TrimEnd("`r", "`n") -cne $value) { throw "Native argument changed: '$value'." }
    }
    $index = Join-Path $env:FIXTURE_REPO 'explicit index'
    [IO.File]::Copy((Join-Path $env:FIXTURE_REPO '.git\index'), $index)
    $candidate = New-GitReviewCandidate -RepositoryRoot $env:FIXTURE_REPO -IndexPath $index
    $snapshot = New-GitTreeSnapshot $candidate
    $base = New-GitTreeSnapshot $candidate -Base
    if ($snapshot.Manifest.Count -ne 2050 -or $base.Manifest.Count -ne 2049) { throw 'Incomplete snapshot manifest.' }
    $actual = [IO.File]::ReadAllBytes((Join-Path $snapshot.Path 'binary.dat'))
    $expected = [IO.File]::ReadAllBytes((Join-Path $env:FIXTURE_REPO 'binary.dat'))
    if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String($expected)) { throw 'Binary bytes changed.' }
    if ([IO.File]::ReadAllText((Join-Path $base.Path 'files\1.txt')) -cne 'base') { throw 'Wrong base bytes.' }
    $null = Invoke-GitSnapshotCheck $snapshot -Name 'runtime check' -FilePath $env:FIXTURE_RUNTIME `
        -ArgumentList @('-NoProfile', '-Command', 'exit 0')
    [IO.File]::WriteAllText((Join-Path $snapshot.Path 'files\1.txt'), 'mutation')
    $rejected = $false
    try { Assert-GitSnapshotIntegrity $snapshot }
    catch {
        if ($_.Exception.Message -notmatch 'changed bytes') { throw }
        $rejected = $true
    }
    if (-not $rejected -or -not $snapshot.Invalidated) { throw 'Integrity mutation was not latched.' }
    Write-Output "Snapshot verified under PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    if ($candidate) { Remove-GitReviewCandidate $candidate }
    Remove-IsolatedProcessContext $probe
}
'@
        $executable = (Get-Command $runtime -CommandType Application -ErrorAction Stop).Source
        $runtimeArguments = @('-NoProfile')
        if ($runtime -eq 'powershell.exe') { $runtimeArguments += @('-ExecutionPolicy', 'Bypass') }
        $runtimeArguments += @('-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
        $result = Invoke-IsolatedProcess -Context $context -FilePath $executable -WorkingDirectory $root `
            -ArgumentList $runtimeArguments `
            -Environment @{
                FIXTURE_HELPER = $script:SnapshotHelper
                FIXTURE_PROCESS_HELPER = Join-Path $script:SnapshotRepoRoot 'scripts\IsolatedProcess.psm1'
                FIXTURE_REPO = $root
                FIXTURE_RUNTIME = $executable
                PSModulePath = $null
            } -AllowFailure
        Assert-True ($result.ExitCode -eq 0) $result.Output
    }
}

Test-Case 'A timed-out validation command invalidates evidence and cannot be accepted as an allowed failure' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $snapshot = New-GitTreeSnapshot $candidate
    Assert-Throws {
        Invoke-GitSnapshotCheck $snapshot -Name 'stalled validation' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -TimeoutSeconds 1
    } 'timed out after 1 seconds'
    Assert-True ($snapshot.Invalidated -and $snapshot.Checks.Count -eq 0) 'Timed-out validation produced successful evidence.'
    Assert-Throws { Assert-GitSnapshotIntegrity $snapshot } 'already invalidated'
}

Test-Case 'Candidate capture leaves source index bytes unchanged' {
    $root = New-StagedFixture
    $index = Join-Path $root '.git\index'
    $before = (Get-FileHash -LiteralPath $index).Hash
    $candidate = New-TestCandidate $root
    $null = New-GitTreeSnapshot $candidate
    Assert-GitCandidateCurrent $candidate
    Assert-True ((Get-FileHash -LiteralPath $index).Hash -ceq $before) 'Capture rewrote the source index.'
}

Test-Case 'SHA-256 repositories retain exact object and materialized byte identities' {
    $root = New-IsolatedGitRepo -ObjectFormat sha256
    $bytes = [byte[]]@(0, 255, 10, 13, 42)
    $null = Add-FixtureIndexBlob $root 'binary.dat' $bytes
    $candidate = New-TestCandidate $root
    Assert-True ($candidate.ObjectFormat -ceq 'sha256' -and $candidate.Tree.Length -eq 64) 'SHA-256 identity was not captured.'
    $snapshot = New-GitTreeSnapshot $candidate
    Assert-SnapshotFiles $snapshot @{ 'binary.dat' = $bytes }
}

foreach ($unsupported in @('symlink', 'submodule', 'LFS pointer')) {
    Test-Case "Unsupported $unsupported fails safely without a content substitute" {
        $root = New-StagedFixture
        if ($unsupported -eq 'submodule') {
            $head = (Invoke-Git $root @('rev-parse', 'HEAD')).Trim()
            $null = Invoke-Git $root @('update-index', '--add', '--cacheinfo', "160000,$head,submodule")
        }
        else {
            $bytes = if ($unsupported -eq 'symlink') { [Text.Encoding]::UTF8.GetBytes('../outside') } else {
                [Text.Encoding]::UTF8.GetBytes("version https://git-lfs.github.com/spec/v1`noid sha256:$('a' * 64)`nsize 20`n")
            }
            $mode = if ($unsupported -eq 'symlink') { '120000' } else { '100644' }
            $null = Add-FixtureIndexBlob $root 'unsupported' $bytes -Mode $mode
        }
        $candidate = New-TestCandidate $root
        Assert-Throws { New-GitTreeSnapshot $candidate } 'Unsupported (symbolic-link|submodule|LFS pointer) input'
    }
}

Test-Case 'NUL discovery preserves a newline name; materialization is exact or explicitly unsupported' {
    $root = New-StagedFixture
    $name = "line`nbreak.txt"
    $bytes = [Text.Encoding]::UTF8.GetBytes("newline-name`n")
    if ($IsWindows) {
        Assert-Throws { Add-FixtureIndexBlob $root $name $bytes } 'Git did not stage the exact fixture path'
        $candidate = New-TestCandidate $root
        $blob = (Invoke-FixtureGit $root @('hash-object', '-w', '--stdin') -InputBytes $bytes).Stdout.Trim()
        $record = [Text.Encoding]::UTF8.GetBytes("100644 blob $blob`t$name`0")
        $tree = (Invoke-FixtureGit $root @('mktree', '-z') -InputBytes $record).Stdout.Trim()
        $raw = Invoke-FixtureGit $root @('diff', '--name-only', '--no-renames', '-z', $candidate.State.Base, $tree)
        $paths = @(& (Get-Module GitSnapshot) { param($Bytes) ConvertFrom-GitNulOutput -Bytes $Bytes } $raw.Bytes)
        Assert-True ($paths -ccontains $name) 'NUL parsing lost a real Git tree newline path.'
        $treeCandidate = $candidate.PSObject.Copy()
        $treeCandidate.Tree = $tree
        Assert-Throws {
            & (Get-Module GitSnapshot) {
                param($Candidate)
                Get-TreeManifest -Candidate $Candidate -SnapshotPath (Join-Path $Candidate.Context.Root 'unrepresentable')
            } $treeCandidate
        } 'Unsupported or unsafe Git path'
    }
    else {
        $null = Add-FixtureIndexBlob $root $name $bytes
        $candidate = New-TestCandidate $root
        Assert-True ($candidate.ChangedPaths -ccontains $name) 'NUL parsing lost a staged newline path.'
        $snapshot = New-GitTreeSnapshot $candidate
        Assert-SnapshotFiles $snapshot @{ 'candidate.txt' = [Text.Encoding]::UTF8.GetBytes('staged'); $name = $bytes }
    }
}

Test-Case 'Executable Git mode is preserved on POSIX and recorded as metadata on Windows' {
    $root = New-StagedFixture
    $null = Invoke-Git $root @('update-index', '--chmod=+x', '--', 'candidate.txt')
    $candidate = New-TestCandidate $root
    $snapshot = New-GitTreeSnapshot $candidate
    Assert-True ($snapshot.Manifest[0].Mode -ceq '100755') 'The manifest lost executable metadata.'
    if ($IsWindows) {
        Assert-True ($snapshot.ModeFidelity -ceq 'metadata-only') 'Windows mode fidelity was overstated.'
        $null = Invoke-GitSnapshotCheck $snapshot -Name 'ordinary Windows check' -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-Command', 'exit 0')
        Assert-Throws {
            Invoke-GitSnapshotCheck $snapshot -Name 'executable check' -FilePath 'pwsh' `
                -ArgumentList @('-NoProfile', '-Command', '[IO.File]::WriteAllText("must-not-run.txt", "ran")') -RequiresPosix
        } 'requires a POSIX host'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $snapshot.Path 'must-not-run.txt'))) 'A required POSIX check executed on Windows.'
    }
    else {
        Assert-True ($snapshot.ModeFidelity -ceq 'exact') 'POSIX fidelity was not recorded.'
        $path = Join-Path $snapshot.Path 'candidate.txt'
        Assert-True ([int][IO.File]::GetUnixFileMode($path) -eq 493) 'Executable mode was transformed.'
        [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]420)
        Assert-Throws { Assert-GitSnapshotIntegrity $snapshot } 'changed mode'
    }
}

Test-Case 'Cleanup failure after a verified commit reports cleanup independently and permits retry' {
    $root = New-StagedFixture
    $candidate = New-TestCandidate $root
    $null = New-GitTreeSnapshot $candidate
    $commit = New-FixtureCommit $root $candidate.Tree $candidate.State.Parents
    $null = Invoke-Git $root @('update-ref', 'HEAD', $commit)
    Assert-GitCandidateCommit $candidate -CommitId $commit
    $lock = [IO.File]::Open((Join-Path $candidate.Context.Root 'locked.txt'), [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if ($IsWindows) {
            $warnings = @()
            $cleanup = Remove-GitReviewCandidate $candidate -ReportFailure -WarningVariable warnings -WarningAction SilentlyContinue
            Assert-True (-not $cleanup.Succeeded -and $cleanup.Error -and $warnings.Count -gt 0) 'Cleanup failure was hidden or success-shaped.'
            Assert-True ($cleanup.Path -ceq $candidate.Context.Root) 'Cleanup did not identify its retry scope.'
            Assert-GitCandidateCommit $candidate -CommitId $commit
            Assert-True ((Invoke-Git $root @('rev-parse', 'HEAD')).Trim() -ceq $commit) 'Cleanup failure changed the successful commit.'
        }
    }
    finally { $lock.Dispose() }
    $cleanup = Remove-GitReviewCandidate $candidate -ReportFailure
    Assert-True ($cleanup.Succeeded -and -not (Test-Path -LiteralPath $cleanup.Path)) 'Retry did not clean the owned context.'
    $null = $script:TestCandidates.Remove($candidate)
}

Test-Case 'Cleanup preview and unowned contexts cannot be reported as successful removals' {
    $candidate = New-TestCandidate (New-StagedFixture)
    $preview = Remove-GitReviewCandidate $candidate -ReportFailure -WhatIf
    Assert-True (-not $preview.Succeeded -and (Test-Path -LiteralPath $preview.Path)) 'Cleanup preview removed state or claimed success.'
    $foreign = New-StagedFixture
    $fake = [pscustomobject]@{ Context = [pscustomobject]@{ Root = $foreign } }
    $failure = Remove-GitReviewCandidate $fake -ReportFailure -WarningAction SilentlyContinue
    Assert-True (-not $failure.Succeeded -and $failure.Error -match 'unowned process context') 'An unowned cleanup was hidden.'
    Assert-Throws { Remove-GitReviewCandidate $fake } 'unowned process context'
    Assert-True (Test-Path -LiteralPath $foreign) 'Unowned content was removed.'
}

Test-Case 'A HEAD-substitution mutant of the documented procedure cannot pass' {
    $root = New-StagedFixture
    $content = Get-Content -LiteralPath (Join-Path $script:SnapshotRepoRoot 'skills\git-commit-review\SKILL.md') -Raw
    $needle = '$snapshot = New-GitTreeSnapshot -Candidate $candidate'
    Assert-True $content.Contains($needle) 'Document mutation target is missing.'
    $mutation = '$candidate.Tree = $candidate.State.Base' + "`n" + $needle
    Assert-Throws { Get-DocumentedSnapshot -RepoRoot $root -Content $content.Replace($needle, $mutation) } 'index tree changed'
}

foreach ($mutant in @('control', 'corrupt materialized bytes', 'add unexpected file')) {
    Test-Case "Executable helper mutation test: $mutant" {
        $root = New-StagedFixture
        $context = $script:GitFixtureContexts[$root]
        $modulePath = Join-Path $context.Root 'GitSnapshot.psm1'
        $source = Get-Content -LiteralPath $script:SnapshotHelper -Raw
        $needle = '    Assert-GitSnapshotIntegrity -Snapshot $snapshot -Exact'
        Assert-True $source.Contains($needle) 'Helper mutation target is missing.'
        if ($mutant -ne 'control') {
            $file = if ($mutant -eq 'add unexpected file') { 'unexpected.txt' } else { 'candidate.txt' }
            $injection = "    [IO.File]::WriteAllText((Join-Path `$snapshot.Path '$file'), 'mutation')`n"
            $source = $source.Replace($needle, $injection + $needle)
        }
        [IO.File]::WriteAllText($modulePath, $source)
        Copy-Item -LiteralPath (Join-Path $script:SnapshotRepoRoot 'scripts\IsolatedProcess.psm1') -Destination $context.Root
        $command = @'
Import-Module $env:FIXTURE_HELPER -ErrorAction Stop
$candidate = $null
try {
    $candidate = New-GitReviewCandidate -RepositoryRoot $env:FIXTURE_REPO
    $null = New-GitTreeSnapshot -Candidate $candidate
}
finally { if ($candidate) { Remove-GitReviewCandidate -Candidate $candidate } }
'@
        $result = Invoke-IsolatedProcess -Context $context -FilePath 'pwsh' -WorkingDirectory $root `
            -ArgumentList @('-NoProfile', '-Command', $command) `
            -Environment @{ FIXTURE_HELPER = $modulePath; FIXTURE_REPO = $root } -AllowFailure
        if ($mutant -eq 'control') { Assert-True ($result.ExitCode -eq 0) $result.Output }
        else { Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'changed bytes|unexpected path') $result.Output }
    }
}

Test-Case 'Inherited Git redirection, homes, hooks, signing, and fsmonitor cannot affect another fixture' {
    $foreign = New-StagedFixture
    $context = $script:GitFixtureContexts[$foreign]
    $before = @{}
    foreach ($path in @('candidate.txt', '.git\index', '.git\config', '.git\HEAD')) {
        $before[$path] = (Get-FileHash -LiteralPath (Join-Path $foreign $path)).Hash
    }
    $hostIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE')
    $command = @'
$ErrorActionPreference = 'Stop'
. $env:FIXTURE_LIBRARY
$root = New-IsolatedGitRepo
try {
    $owned = $script:GitFixtureContexts[$root]
    $hooks = Join-Path $owned.Root 'hostile-hooks'
    $null = New-Item -ItemType Directory -Path $hooks
    [IO.File]::WriteAllText((Join-Path $hooks 'pre-commit'), "#!/bin/sh`nexit 88`n")
    if (-not $IsWindows) { [IO.File]::SetUnixFileMode((Join-Path $hooks 'pre-commit'), [IO.UnixFileMode]493) }
    $null = Invoke-Git $root @('config', '--local', 'core.hooksPath', $hooks)
    $null = Invoke-Git $root @('config', '--local', 'core.fsmonitor', 'missing-fsmonitor-command')
    $null = Invoke-Git $root @('config', '--local', 'commit.gpgSign', 'true')
    $null = Invoke-Git $root @('config', '--local', 'gpg.program', 'missing-signing-command')
    Set-RepoFile $root 'owned.txt' 'owned'
    $null = Invoke-Git $root @('add', '.')
    $null = Invoke-Git $root @('commit', '-q', '-m', 'controlled')
    $failed = $false
    try { $null = Invoke-Git $root @('not-a-git-command') } catch { $failed = $_.Exception.Message -match 'failed with exit' }
    if (-not $failed) { throw 'Native failure was not explicit.' }
    $probe = Invoke-IsolatedProcess -Context $owned -FilePath 'pwsh' -WorkingDirectory $root -ArgumentList @(
        '-NoProfile', '-Command', '[pscustomobject]@{ Home=$HOME; Profile=$env:USERPROFILE; Index=$env:GIT_INDEX_FILE; Dir=$env:GIT_DIR; Work=$env:GIT_WORK_TREE } | ConvertTo-Json -Compress'
    )
    $values = $probe.Stdout | ConvertFrom-Json
    if ($values.Home -ne $owned.Home -or $values.Profile -ne $owned.Home -or $values.Index -or $values.Dir -or $values.Work) {
        throw 'Child home or Git redirection escaped isolation.'
    }
}
finally { Remove-TestPath $root }
'@
    $result = Invoke-IsolatedProcess -Context $context -FilePath 'pwsh' -WorkingDirectory $context.Root `
        -ArgumentList @('-NoProfile', '-Command', $command) -Environment @{
            FIXTURE_LIBRARY = Join-Path $PSScriptRoot 'New-GitSnapshotFixture.ps1'
            GIT_INDEX_FILE = Join-Path $foreign '.git\index'
            GIT_DIR = Join-Path $foreign '.git'
            GIT_WORK_TREE = $foreign
            GIT_CONFIG_GLOBAL = Join-Path $foreign '.git\config'
            GIT_CONFIG_COUNT = '1'
            GIT_CONFIG_KEY_0 = 'core.hooksPath'
            GIT_CONFIG_VALUE_0 = $foreign
            HOME = $context.Home
            USERPROFILE = $context.Home
        }
    Assert-True ($result.ExitCode -eq 0) $result.Output
    foreach ($path in $before.Keys) {
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $foreign $path)).Hash -ceq $before[$path]) "Foreign fixture changed: $path"
    }
    Assert-True ([Environment]::GetEnvironmentVariable('GIT_INDEX_FILE') -ceq $hostIndex) 'Caller environment was modified.'
}

Write-Host ''
if ($script:TestsFailed -eq 0) {
    Write-Host "✅ All $script:TestsPassed snapshot regression tests passed." -ForegroundColor Green
    if ($IsWindows) { Write-Host 'POSIX executable-mode, newline-file, and real hook-dispatch branches require POSIX verification.' }
    exit 0
}
Write-Host "❌ $script:TestsFailed of $($script:TestsPassed + $script:TestsFailed) snapshot regression tests failed." -ForegroundColor Red
exit 1
