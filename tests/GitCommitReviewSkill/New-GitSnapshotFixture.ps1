#Requires -Version 7.0
<#
.SYNOPSIS
    Builds isolated, disposable real Git repositories used to verify the
    staged-index snapshot procedure documented in
    skills\git-commit-review\SKILL.md sections 2 and 7.
.DESCRIPTION
    No side effects outside $env:TEMP. Every helper here only ever operates
    against a caller-supplied isolated repo root created by
    New-IsolatedGitRepo; the real repository's own Git state is never
    touched. Callers must remove the returned repo root (and any snapshot/
    archive paths returned alongside it) when done.
#>

$ErrorActionPreference = 'Stop'

function New-IsolatedGitRepo {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory, initializes it as a Git
        repository with a local-only identity, and disables autocrlf so
        blob content comparisons stay byte-exact. Caller is responsible for
        cleanup via Remove-TestPath.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-gcr-git-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null

    $null = Invoke-Git -RepoRoot $path -GitArgs @('init', '-q', '-b', 'main')
    $null = Invoke-Git -RepoRoot $path -GitArgs @('config', 'user.name', 'Test Engineer')
    $null = Invoke-Git -RepoRoot $path -GitArgs @('config', 'user.email', 'test-engineer@example.invalid')
    $null = Invoke-Git -RepoRoot $path -GitArgs @('config', 'core.autocrlf', 'false')

    $path
}

function Remove-TestPath {
    <#
    .SYNOPSIS
        Removes exactly one disposable temp path (a repo root, snapshot
        directory, or archive file) created by this fixture. Never touches
        anything outside $env:TEMP.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-RepoFile {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Content
    )

    Set-Content -LiteralPath (Join-Path $RepoRoot $RelativePath) -Value $Content -Encoding utf8 -NoNewline
}

function Invoke-Git {
    <#
    .SYNOPSIS
        Runs one git command against an isolated repo root and returns its
        combined stdout/stderr, throwing on a non-zero exit code.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$GitArgs
    )

    $output = & git -C $RepoRoot @GitArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit $LASTEXITCODE in ${RepoRoot}: $output"
    }
    $output
}

function Get-GitBlobContent {
    <#
    .SYNOPSIS
        Returns the raw blob content of one path as recorded inside a given
        tree object (never the working tree), via git show <tree>:<path>.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Tree,
        [Parameter(Mandatory)][string]$Path
    )

    (Invoke-Git -RepoRoot $RepoRoot -GitArgs @('show', "${Tree}:${Path}")).TrimEnd("`r", "`n")
}

function New-Snapshot {
    <#
    .SYNOPSIS
        Materializes a tree object into a fresh temp directory using the
        exact git archive + tar sequence documented in SKILL.md section 2.
        Returns an object with SnapshotPath and ArchivePath so the caller
        can clean both up.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Tree
    )

    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-gcr-git-archive-" + [guid]::NewGuid() + '.tar')
    $snapshotPath = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-gcr-git-snapshot-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $snapshotPath | Out-Null

    Invoke-Git -RepoRoot $RepoRoot -GitArgs @('archive', '--format=tar', "--output=$archivePath", $Tree)
    tar -xf $archivePath -C $snapshotPath
    if ($LASTEXITCODE -ne 0) { throw "tar extraction of the candidate snapshot failed with exit $LASTEXITCODE." }

    [pscustomobject]@{ SnapshotPath = $snapshotPath; ArchivePath = $archivePath }
}

function Get-SnapshotFileList {
    <#
    .SYNOPSIS
        Returns the materialized snapshot's file paths as forward-slash
        relative paths, for direct comparison against git ls-tree output.
    #>
    param([Parameter(Mandatory)][string]$SnapshotPath)

    Get-ChildItem -LiteralPath $SnapshotPath -Recurse -File |
        ForEach-Object { $_.FullName.Substring($SnapshotPath.Length + 1) -replace '\\', '/' }
}
