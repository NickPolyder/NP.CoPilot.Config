#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$script:SnapshotRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:SnapshotHelper = Join-Path $script:SnapshotRepoRoot 'scripts\GitSnapshot.psm1'
Import-Module (Join-Path $script:SnapshotRepoRoot 'scripts\IsolatedProcess.psm1') -ErrorAction Stop
Import-Module $script:SnapshotHelper -ErrorAction Stop
$script:GitFixtureContexts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

function New-IsolatedGitRepo {
    param([ValidateSet('sha1', 'sha256')][string]$ObjectFormat = 'sha1')

    $context = New-IsolatedProcessContext
    $path = Join-Path $context.Root 'repo'
    $null = New-Item -ItemType Directory -Path $path
    $script:GitFixtureContexts.Add($path, $context)
    try {
        $null = Invoke-Git $path @('init', '-q', '-b', 'main', "--object-format=$ObjectFormat")
        $null = Invoke-Git $path @('config', '--local', 'user.name', 'Snapshot Fixture')
        $null = Invoke-Git $path @('config', '--local', 'user.email', 'snapshot@example.invalid')
        $null = Invoke-Git $path @('config', '--local', 'core.autocrlf', 'false')
        $path
    }
    catch {
        Remove-TestPath -Path $path
        throw
    }
}

function Remove-TestPath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not $script:GitFixtureContexts.ContainsKey($Path)) {
        throw "Refusing to remove an unregistered Git fixture: $Path"
    }
    Remove-IsolatedProcessContext -Context $script:GitFixtureContexts[$Path]
    $null = $script:GitFixtureContexts.Remove($Path)
}

function Set-RepoFile {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    if (-not $script:GitFixtureContexts.ContainsKey($RepoRoot)) { throw 'Not an owned Git fixture.' }
    $path = Join-Path $RepoRoot $RelativePath
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$GitArgs,
        [AllowEmptyCollection()][byte[]]$InputBytes = @(),
        [hashtable]$Environment = @{},
        [switch]$AllowFailure
    )

    if (-not $script:GitFixtureContexts.ContainsKey($RepoRoot)) { throw 'Not an owned Git fixture.' }
    Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$RepoRoot] -FilePath 'git' `
        -ArgumentList (@('--no-pager', '-C', $RepoRoot) + $GitArgs) -WorkingDirectory $RepoRoot `
        -InputBytes $InputBytes -Environment $Environment -AllowFailure:$AllowFailure
}

function Invoke-Git {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string[]]$GitArgs)

    (Invoke-FixtureGit -RepoRoot $RepoRoot -GitArgs $GitArgs).Stdout
}

function Add-FixtureIndexBlob {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$GitPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [string]$Mode = '100644'
    )

    $oid = (Invoke-FixtureGit $RepoRoot @('hash-object', '-w', '--stdin') -InputBytes $Bytes).Stdout.Trim()
    $record = [Text.Encoding]::UTF8.GetBytes("$Mode $oid`t$GitPath`0")
    $null = Invoke-FixtureGit $RepoRoot @('update-index', '-z', '--index-info') -InputBytes $record
    $paths = (Invoke-FixtureGit $RepoRoot @('ls-files', '-z')).Stdout.Split([char]0)
    if ($paths -cnotcontains $GitPath) {
        throw "Git did not stage the exact fixture path '$GitPath'; native update-index may ignore unsupported names even with exit 0."
    }
    $oid
}

function Get-DocumentedSnapshot {
    param([Parameter(Mandatory)][string]$RepoRoot, [string]$Content)

    if (-not $Content) {
        $Content = Get-Content -LiteralPath (Join-Path $script:SnapshotRepoRoot 'skills\git-commit-review\SKILL.md') -Raw
    }
    $match = [regex]::Match($Content, '(?s)<!-- tested-snapshot:start -->\r?\n```powershell\r?\n(?<code>.*?)\r?\n```\r?\n<!-- tested-snapshot:end -->')
    if (-not $match.Success) { throw 'The tested snapshot procedure block is missing or malformed.' }
    $procedure = [scriptblock]::Create(
        "param(`$repositoryRoot, `$snapshotHelper)`n`$candidate = `$null`n`$snapshot = `$null`n`$baseSnapshot = `$null`ntry {`n" + $match.Groups['code'].Value +
        "`n[pscustomobject]@{ Candidate = `$candidate; Snapshot = `$snapshot; BaseSnapshot = `$baseSnapshot }`n} catch { if (`$candidate) { Remove-GitReviewCandidate -Candidate `$candidate }; throw }"
    )
    & $procedure $RepoRoot $script:SnapshotHelper
}
