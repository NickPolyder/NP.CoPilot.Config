#Requires -Version 7.0
<#
.SYNOPSIS
    Captures exact Git candidates and validates raw-tree snapshots.
.DESCRIPTION
    See scripts\README.md for the supported filesystem, approval, and process
    contracts. This module never stages, commits, amends, or rewrites the source
    index. Git write-tree operates only on a disposable copy of that index.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'IsolatedProcess.psm1') -ErrorAction Stop
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)

function Invoke-CandidateGit {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)][string[]]$Arguments,
        [AllowEmptyCollection()][byte[]]$InputBytes = @(),
        [hashtable]$Environment = @{},
        [switch]$AllowFailure
    )

    Invoke-IsolatedProcess -Context $Candidate.Context -FilePath 'git' `
        -ArgumentList (@('--no-pager', '-C', $Candidate.RepositoryRoot) + $Arguments) `
        -WorkingDirectory $Candidate.RepositoryRoot -InputBytes $InputBytes `
        -Environment $Environment -AllowFailure:$AllowFailure
}

function Get-CandidateGitText {
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)][string[]]$Arguments)

    (Invoke-CandidateGit -Candidate $Candidate -Arguments $Arguments).Stdout.TrimEnd("`r", "`n")
}

function Get-GitCommitState {
    param([Parameter(Mandatory)]$Candidate)

    $symbolic = Invoke-CandidateGit $Candidate @('symbolic-ref', '--quiet', '--no-recurse', 'HEAD') -AllowFailure
    if ($symbolic.ExitCode -notin @(0, 1)) {
        throw "Git HEAD discovery failed (exit $($symbolic.ExitCode)): $($symbolic.Output)"
    }
    $destination = if ($symbolic.ExitCode -eq 0) { $symbolic.Stdout.TrimEnd("`r", "`n") } else { 'HEAD' }
    if ($symbolic.ExitCode -eq 0 -and $destination -cnotmatch '^refs/heads/.+') {
        throw "Unsupported symbolic commit destination '$destination'; expected a direct branch ref."
    }
    if ($symbolic.ExitCode -eq 0) {
        $resolved = Get-CandidateGitText $Candidate @('symbolic-ref', '--quiet', 'HEAD')
        if ($resolved -cne $destination) {
            throw 'Symbolic-ref chains are not supported commit destinations.'
        }
    }
    $headResult = Invoke-CandidateGit $Candidate @('rev-parse', '--verify', '--quiet', 'HEAD^{commit}') -AllowFailure
    if ($headResult.ExitCode -notin @(0, 1)) {
        throw "Git base discovery failed (exit $($headResult.ExitCode)): $($headResult.Output)"
    }
    $head = $null
    if ($headResult.ExitCode -eq 0) {
        $head = $headResult.Stdout.Trim()
    }
    elseif ($symbolic.ExitCode -eq 1) {
        throw 'Detached HEAD does not resolve to a commit.'
    }
    else {
        $refResult = Invoke-CandidateGit $Candidate @('show-ref', '--verify', '--quiet', $destination) -AllowFailure
        if ($refResult.ExitCode -ne 1) {
            throw "Cannot establish an unborn branch at '$destination' (exit $($refResult.ExitCode)): $($refResult.Output)"
        }
    }

    foreach ($operation in @('CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer')) {
        $operationPath = Get-CandidateGitText $Candidate @('rev-parse', '--path-format=absolute', '--git-path', $operation)
        if (Test-Path -LiteralPath $operationPath) {
            throw "Unsupported in-progress Git operation '$operation'; finish it before this commit workflow."
        }
    }
    $parents = [Collections.Generic.List[string]]::new()
    if ($head) { $parents.Add($head) }
    $mergePath = Get-CandidateGitText $Candidate @('rev-parse', '--path-format=absolute', '--git-path', 'MERGE_HEAD')
    $mergeMode = ''
    if (Test-Path -LiteralPath $mergePath) {
        if (-not $head) { throw 'An unborn branch cannot have merge parents.' }
        foreach ($parent in [IO.File]::ReadAllLines($mergePath)) {
            if ($parent -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                throw 'MERGE_HEAD contains an invalid parent identity.'
            }
            $resolvedParent = Get-CandidateGitText $Candidate @('rev-parse', '--verify', "$parent^{commit}")
            if ($resolvedParent -cne $parent -or $parents.Contains($parent)) {
                throw 'MERGE_HEAD contains a duplicate or non-commit parent.'
            }
            $parents.Add($parent)
        }
        if ($parents.Count -lt 2) { throw 'MERGE_HEAD contains no merge parent.' }
        $modePath = Get-CandidateGitText $Candidate @('rev-parse', '--path-format=absolute', '--git-path', 'MERGE_MODE')
        if (Test-Path -LiteralPath $modePath) { $mergeMode = [IO.File]::ReadAllText($modePath) }
    }
    $state = if (-not $head) { 'unborn' } elseif ($symbolic.ExitCode -eq 1) { 'detached' } else { 'symbolic' }
    $base = if ($head) { $head } else { Get-CandidateGitText $Candidate @('hash-object', '-w', '-t', 'tree', '--stdin') }
    [pscustomobject]@{
        Head = $head
        Base = $base
        RefState = $state
        DestinationRef = $destination
        Parents = $parents.ToArray()
        MergeMode = $mergeMode
    }
}

function Get-CopiedIndexTree {
    param([Parameter(Mandatory)]$Candidate)

    $copy = Join-Path $Candidate.Context.Root ('index-' + [guid]::NewGuid().ToString('N'))
    try {
        if (Test-Path -LiteralPath $Candidate.IndexPath) {
            $item = Get-Item -LiteralPath $Candidate.IndexPath -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "The candidate index is not a regular file: $($Candidate.IndexPath)"
            }
            $before = (Get-FileHash -LiteralPath $Candidate.IndexPath -Algorithm SHA256).Hash
            [IO.File]::Copy($Candidate.IndexPath, $copy)
            $copied = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
            $after = (Get-FileHash -LiteralPath $Candidate.IndexPath -Algorithm SHA256).Hash
            if ($before -cne $copied -or $before -cne $after) {
                throw 'The source index changed while it was being captured.'
            }
        }
        elseif ($Candidate.ExplicitIndex) {
            throw "The explicitly selected candidate index is missing: $($Candidate.IndexPath)"
        }
        $result = Invoke-CandidateGit $Candidate @('write-tree') -Environment @{ GIT_INDEX_FILE = $copy }
        $tree = $result.Stdout.Trim()
        if ($tree -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
            throw 'Git write-tree did not return one valid candidate tree identity.'
        }
        $tree
    }
    finally {
        foreach ($path in @($copy, "$copy.lock")) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
}

function ConvertFrom-GitNulOutput {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $text = $script:Utf8.GetString($Bytes)
    if ($text.Length -eq 0) { return }
    if (-not $text.EndsWith("`0")) { throw 'Git did not return terminated NUL-delimited output.' }
    $text.Substring(0, $text.Length - 1).Split([char]0)
}

function New-GitReviewCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$IndexPath,
        [switch]$AllowEmpty
    )

    $context = New-IsolatedProcessContext
    $candidate = [pscustomobject]@{
        Context = $context
        RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
        GitDirectory = ''
        IndexPath = ''
        ExplicitIndex = -not [string]::IsNullOrEmpty($IndexPath)
        ObjectFormat = ''
        State = $null
        Tree = ''
        ChangedPaths = [string[]]@()
        DiffBytes = [byte[]]@()
    }
    try {
        $gitRoot = Get-CandidateGitText $candidate @('rev-parse', '--show-toplevel')
        if ([IO.Path]::GetFullPath($gitRoot) -ne $candidate.RepositoryRoot.TrimEnd('\', '/')) {
            throw 'RepositoryRoot must identify the Git worktree root, not a subdirectory.'
        }
        $candidate.GitDirectory = Get-CandidateGitText $candidate @('rev-parse', '--absolute-git-dir')
        $candidate.ObjectFormat = Get-CandidateGitText $candidate @('rev-parse', '--show-object-format')
        if ($candidate.ObjectFormat -notin @('sha1', 'sha256')) { throw 'Unsupported Git object format.' }
        $candidate.IndexPath = if ($candidate.ExplicitIndex) {
            if (-not [IO.Path]::IsPathFullyQualified($IndexPath)) { throw 'IndexPath must be an explicit absolute path.' }
            [IO.Path]::GetFullPath($IndexPath)
        }
        else {
            Get-CandidateGitText $candidate @('rev-parse', '--path-format=absolute', '--git-path', 'index')
        }
        $candidate.State = Get-GitCommitState $candidate
        $candidate.Tree = Get-CopiedIndexTree $candidate
        $paths = Invoke-CandidateGit $candidate @(
            'diff', '--no-ext-diff', '--no-textconv', '--no-renames', '--name-only', '-z',
            $candidate.State.Base, $candidate.Tree, '--'
        )
        $candidate.ChangedPaths = [string[]]@(ConvertFrom-GitNulOutput $paths.Bytes)
        if (-not $AllowEmpty -and $candidate.ChangedPaths.Count -eq 0) {
            throw 'The index has no changes relative to the captured base.'
        }
        $candidate.DiffBytes = (Invoke-CandidateGit $candidate @(
            'diff', '--no-ext-diff', '--no-textconv', '--binary', '--full-index', '--find-renames',
            $candidate.State.Base, $candidate.Tree, '--'
        )).Bytes
        Assert-GitCandidateCurrent -Candidate $candidate
        $candidate
    }
    catch {
        Remove-IsolatedProcessContext -Context $context
        throw
    }
}

function Assert-GitCandidateCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate)

    $current = Get-GitCommitState $Candidate
    foreach ($property in @('Head', 'Base', 'RefState', 'DestinationRef', 'MergeMode')) {
        if ($current.$property -cne $Candidate.State.$property) {
            throw "Candidate approval invalidated: $property changed."
        }
    }
    if (($current.Parents -join "`n") -cne ($Candidate.State.Parents -join "`n")) {
        throw 'Candidate approval invalidated: the ordered parent list changed.'
    }
    if ((Get-CopiedIndexTree $Candidate) -cne $Candidate.Tree) {
        throw 'Candidate approval invalidated: the index tree changed.'
    }
}

function Get-SnapshotPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$GitPath)

    $parts = $GitPath.Split('/')
    foreach ($part in $parts) {
        if (-not $part -or $part -in @('.', '..', '.git') -or $part.Contains('\') -or
            $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "Unsupported or unsafe Git path: '$GitPath'."
        }
        if ($IsWindows -and ($part -match '[. ]$' -or $part -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)')) {
            throw "Git path cannot be represented faithfully on Windows: '$GitPath'."
        }
    }
    $path = $Root
    foreach ($part in $parts) { $path = Join-Path $path $part }
    $path
}

function Get-TreeManifest {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)][string]$SnapshotPath,
        [string]$Tree = $Candidate.Tree
    )

    $output = Invoke-CandidateGit $Candidate @('ls-tree', '-r', '-z', '--full-tree', $Tree)
    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $paths = [Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($record in @(ConvertFrom-GitNulOutput $output.Bytes)) {
        if ($record -cnotmatch '\A(?<mode>[0-7]{6}) (?<type>blob|commit) (?<oid>[0-9a-f]{40}|[0-9a-f]{64})\t(?<path>[\s\S]+)\z') {
            throw 'Git ls-tree returned an unsupported tree entry.'
        }
        $entry = [pscustomobject]@{
            Path = $Matches.path
            Mode = $Matches.mode
            ObjectId = $Matches.oid
        }
        $null = Get-SnapshotPath -Root $SnapshotPath -GitPath $entry.Path
        if (-not $paths.Add($entry.Path)) { throw "Filesystem path collision in captured tree: '$($entry.Path)'." }
        switch ($entry.Mode) {
            '100644' { }
            '100755' {
                if ($IsWindows) {
                    throw "Git mode 100755 cannot be faithfully represented on Windows: '$($entry.Path)'. Use a POSIX filesystem."
                }
            }
            '120000' { throw "Unsupported symbolic-link input '$($entry.Path)'; never replace it with a regular file or follow its target." }
            '160000' { throw "Unsupported submodule input '$($entry.Path)'; recorded gitlink content requires a separately verified materializer." }
            default { throw "Unsupported Git mode '$($entry.Mode)' for '$($entry.Path)'." }
        }
        $entry
    }
}

function Get-RawBlobHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ObjectFormat)

    $stream = [IO.File]::OpenRead($Path)
    $algorithm = if ($ObjectFormat -eq 'sha256') { [Security.Cryptography.HashAlgorithmName]::SHA256 } else { [Security.Cryptography.HashAlgorithmName]::SHA1 }
    $hash = [Security.Cryptography.IncrementalHash]::CreateHash($algorithm)
    try {
        $hash.AppendData([Text.Encoding]::ASCII.GetBytes("blob $($stream.Length)`0"))
        $buffer = [byte[]]::new(65536)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $hash.AppendData($buffer, 0, $read)
        }
        ([BitConverter]::ToString($hash.GetHashAndReset())).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $hash.Dispose()
    }
}

function New-GitTreeSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate, [switch]$Base)

    Assert-GitCandidateCurrent -Candidate $Candidate
    $tree = if ($Base) {
        Get-CandidateGitText $Candidate @('rev-parse', '--verify', "$($Candidate.State.Base)^{tree}")
    }
    else { $Candidate.Tree }
    $path = Join-Path $Candidate.Context.Root ('snapshot-' + [guid]::NewGuid().ToString('N'))
    $snapshot = [pscustomobject]@{
        Candidate = $Candidate
        Role = $(if ($Base) { 'base' } else { 'candidate' })
        Tree = $tree
        Path = $path
        Manifest = @()
        Invalidated = $false
        InvalidReason = ''
        Checks = [Collections.Generic.List[object]]::new()
    }
    $snapshot.Manifest = @(Get-TreeManifest -Candidate $Candidate -SnapshotPath $path -Tree $tree)
    $null = New-Item -ItemType Directory -Path $path
    foreach ($entry in $snapshot.Manifest) {
        $destination = Get-SnapshotPath -Root $path -GitPath $entry.Path
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        $blob = Invoke-CandidateGit $Candidate @('cat-file', 'blob', $entry.ObjectId)
        $prefix = [Text.Encoding]::ASCII.GetString($blob.Bytes, 0, [Math]::Min($blob.Bytes.Length, 200))
        if ($prefix -match '\Aversion https://git-lfs\.github\.com/spec/v1(?:\r?\n|$)') {
            throw "Unsupported LFS pointer input '$($entry.Path)'; pointer bytes are not the recorded LFS payload."
        }
        [IO.File]::WriteAllBytes($destination, $blob.Bytes)
        if (-not $IsWindows) {
            if (-not ([IO.File].GetMethods().Name -contains 'SetUnixFileMode')) {
                throw 'POSIX mode fidelity requires PowerShell 7.3 or newer; no chmod approximation is used.'
            }
            $mode = if ($entry.Mode -eq '100755') { 493 } else { 420 }
            [IO.File]::SetUnixFileMode($destination, [IO.UnixFileMode]$mode)
        }
    }
    Assert-GitSnapshotIntegrity -Snapshot $snapshot -Exact
    Assert-GitCandidateCurrent -Candidate $Candidate
    $snapshot
}

function Assert-GitSnapshotIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot, [switch]$Exact)

    if ($Snapshot.Invalidated) {
        throw "Snapshot evidence already invalidated: $($Snapshot.InvalidReason) Restoring bytes cannot restore that evidence; create a new snapshot and rerun checks."
    }
    try {
        $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $Snapshot.Manifest) {
            $null = $expected.Add($entry.Path)
            $parent = $entry.Path
            while ($parent.Contains('/')) {
                $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
                $null = $expected.Add($parent)
            }
        }
        $root = Get-Item -LiteralPath $Snapshot.Path -Force
        if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Snapshot root is missing, linked, or not a directory.'
        }
        $actual = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($Snapshot.Path)
        while ($pending.Count -gt 0) {
            foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
                $relative = [IO.Path]::GetRelativePath($Snapshot.Path, $item.FullName).Replace('\', '/')
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Snapshot contains a linked path '$relative'; it is not an ordinary build output."
                }
                if ($Exact -and -not $expected.Contains($relative)) {
                    throw "Snapshot contains an unexpected path '$relative'."
                }
                $actual.Add($relative, $item)
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
        foreach ($entry in $Snapshot.Manifest) {
            if (-not $actual.ContainsKey($entry.Path)) { throw "Snapshot is missing tracked input '$($entry.Path)'." }
            $item = $actual[$entry.Path]
            if ($item.PSIsContainer) { throw "Snapshot tracked input '$($entry.Path)' changed file type." }
            if (-not $IsWindows) {
                $expectedMode = if ($entry.Mode -eq '100755') { 493 } else { 420 }
                if ([int][IO.File]::GetUnixFileMode($item.FullName) -ne $expectedMode) {
                    throw "Snapshot tracked input '$($entry.Path)' changed mode."
                }
            }
            if ((Get-RawBlobHash -Path $item.FullName -ObjectFormat $Snapshot.Candidate.ObjectFormat) -cne $entry.ObjectId) {
                throw "Snapshot tracked input '$($entry.Path)' changed bytes."
            }
        }
    }
    catch {
        $Snapshot.Invalidated = $true
        $Snapshot.InvalidReason = $_.Exception.Message
        throw
    }
}

function Invoke-GitSnapshotCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ArgumentList,
        [string[]]$RequiredPaths = @()
    )

    if ($Snapshot.Role -cne 'candidate' -or $Snapshot.Tree -cne $Snapshot.Candidate.Tree) {
        throw 'Validation requires the captured candidate snapshot; base context is read-only.'
    }
    Assert-GitSnapshotIntegrity -Snapshot $Snapshot
    Assert-GitCandidateCurrent -Candidate $Snapshot.Candidate
    try {
        foreach ($required in $RequiredPaths) {
            $gitPath = $required.Replace('\', '/')
            if ($gitPath -cnotin $Snapshot.Manifest.Path) {
                throw "Declared required validation input '$required' is missing from the candidate tree."
            }
            $null = Get-SnapshotPath -Root $Snapshot.Path -GitPath $gitPath
        }
        $result = Invoke-IsolatedProcess -Context $Snapshot.Candidate.Context -FilePath $FilePath `
            -ArgumentList $ArgumentList -WorkingDirectory $Snapshot.Path -AllowFailure
        Assert-GitSnapshotIntegrity -Snapshot $Snapshot
        Assert-GitCandidateCurrent -Candidate $Snapshot.Candidate
        if ($result.ExitCode -ne 0) {
            throw "Snapshot check '$Name' failed with exit $($result.ExitCode): $($result.Output)"
        }
        $Snapshot.Checks.Add([pscustomobject]@{ Name = $Name; Tree = $Snapshot.Candidate.Tree; ExitCode = $result.ExitCode })
        $result
    }
    catch {
        $Snapshot.Invalidated = $true
        $Snapshot.InvalidReason = $_.Exception.Message
        throw
    }
}

function Assert-GitCandidateCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)][string]$CommitId)

    if ($CommitId -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw 'CommitId must be an exact commit object ID.' }
    $commit = Get-CandidateGitText $Candidate @('cat-file', 'commit', $CommitId)
    $headers = ($commit -split "`n`n", 2)[0] -split "`n"
    $tree = @($headers | Where-Object { $_ -cmatch '^tree ' } | ForEach-Object { $_.Substring(5) })
    $parents = @($headers | Where-Object { $_ -cmatch '^parent ' } | ForEach-Object { $_.Substring(7) })
    if ($tree.Count -ne 1 -or $tree[0] -cne $Candidate.Tree) {
        throw 'Committed tree differs from the validated candidate. Stop delivery; do not automatically amend.'
    }
    if (($parents -join "`n") -cne ($Candidate.State.Parents -join "`n")) {
        throw 'Committed ordered parent list differs from the approved candidate. Stop delivery; do not automatically amend.'
    }
    $current = Get-GitCommitState $Candidate
    $expectedState = if ($Candidate.State.RefState -eq 'unborn') { 'symbolic' } else { $Candidate.State.RefState }
    if ($current.RefState -cne $expectedState -or $current.DestinationRef -cne $Candidate.State.DestinationRef -or $current.Head -cne $CommitId) {
        throw 'Committed destination/ref state differs from the approved candidate. Stop delivery; do not automatically amend.'
    }
}

function Remove-GitReviewCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate)

    Remove-IsolatedProcessContext -Context $Candidate.Context
}

Export-ModuleMember -Function New-GitReviewCandidate, New-GitTreeSnapshot, Assert-GitSnapshotIntegrity,
    Invoke-GitSnapshotCheck, Assert-GitCandidateCurrent, Assert-GitCandidateCommit, Remove-GitReviewCandidate
