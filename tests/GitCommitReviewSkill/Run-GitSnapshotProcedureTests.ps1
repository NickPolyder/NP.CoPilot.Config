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
    foreach ($name in @('unchanged.txt', 'modified.txt', 'deleted.txt', 'old name.txt', 'unstaged.txt')) {
        $expectedBase[$name] = [Text.Encoding]::UTF8.GetBytes("original:$name`n")
    }
    Assert-SnapshotFiles $documented.BaseSnapshot $expectedBase
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

Test-Case 'Executable Git mode is preserved on POSIX or rejected explicitly on Windows' {
    $root = New-StagedFixture
    $null = Invoke-Git $root @('update-index', '--chmod=+x', '--', 'candidate.txt')
    $candidate = New-TestCandidate $root
    if ($IsWindows) { Assert-Throws { New-GitTreeSnapshot $candidate } '100755 cannot be faithfully represented on Windows' }
    else {
        $snapshot = New-GitTreeSnapshot $candidate
        $path = Join-Path $snapshot.Path 'candidate.txt'
        Assert-True ([int][IO.File]::GetUnixFileMode($path) -eq 493) 'Executable mode was transformed.'
        [IO.File]::SetUnixFileMode($path, [IO.UnixFileMode]420)
        Assert-Throws { Assert-GitSnapshotIntegrity $snapshot } 'changed mode'
    }
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
