#Requires -Version 7.0
<#
.SYNOPSIS
    Builds isolated, disposable git-repository fixtures and invocation
    helpers for install-project.ps1 tests.
.DESCRIPTION
    No side effects outside $env:TEMP. Every helper here only ever writes to
    a caller-supplied fixture root; none of them touch this repository's own
    working tree, git state, or the real Copilot home. install-project.ps1
    itself is never modified — it is only invoked out-of-process with
    -TargetPath pointed at a disposable temporary git repository built by
    `git init`. Callers must remove the returned fixture root when done
    (Remove-ProjectFixtureRoot / try-finally).
#>

$ErrorActionPreference = 'Stop'

# tests\InstallProject\New-InstallProjectFixture.ps1 -> repo root is two levels up.
$script:InstallProjectRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:InstallProjectScriptPath = Join-Path $script:InstallProjectRepoRoot 'install-project.ps1'
$script:TemplatesDir = Join-Path $script:InstallProjectRepoRoot 'templates'
$script:StateDirName = '.np-copilot-project-installer'
$script:GitignoreMarker = '# Local Copilot preferences (personal, not shared)'
$script:GitignoreEntry = '.github/instructions/local-preferences.instructions.md'

function New-GitFixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory initialized as a real git
        repository (via `git init -q`), to use as an isolated -TargetPath.
        Caller is responsible for cleanup.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-installproj-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null
    $gitOutput = & git init -q $path 2>&1
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        throw "git init failed for fixture root '$path': $gitOutput"
    }
    $path
}

function New-NonGitFixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory that is deliberately NOT a git
        repository, for preflight-rejection tests. Caller is responsible
        for cleanup.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-installproj-nogit-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null
    $path
}

function Remove-ProjectFixtureRoot {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-InstallProjectScriptCopy {
    <#
    .SYNOPSIS
        Copies install-project.ps1 and the repo's templates\ directory into
        a fresh, disposable temp directory, so a test can simulate a source
        template revision (by editing the COPY's templates) without ever
        mutating this repository's real templates. $PSScriptRoot-relative
        resolution inside install-project.ps1 means invoking the copy makes
        it read templates from the copy, not from the real repo.
        Caller is responsible for cleanup (Remove-ProjectFixtureRoot).
    #>
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-installproj-scriptcopy-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root | Out-Null
    $copiedScriptPath = Join-Path $root 'install-project.ps1'
    Copy-Item -LiteralPath $script:InstallProjectScriptPath -Destination $copiedScriptPath -Force
    $copiedTemplatesDir = Join-Path $root 'templates'
    Copy-Item -LiteralPath $script:TemplatesDir -Destination $copiedTemplatesDir -Recurse -Force
    [pscustomobject]@{ Root = $root; ScriptPath = $copiedScriptPath; TemplatesDir = $copiedTemplatesDir }
}

function Set-InstallProjectScriptCopyTemplateContent {
    <#
    .SYNOPSIS
        Overwrites one template file inside an isolated script-copy fixture
        (see New-InstallProjectScriptCopy) to simulate a source template
        revision landing in this repo. Only ever touches the disposable
        copy's templates directory, never the real repo's templates.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptCopyTemplatesDir,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Content
    )
    $path = Join-Path $ScriptCopyTemplatesDir $FileName
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8 -NoNewline
}

function Invoke-InstallProject {
    <#
    .SYNOPSIS
        Runs install-project.ps1 out-of-process against an isolated
        -TargetPath. Returns exit code + combined stdout/stderr. Pass
        -ScriptPath to target an isolated script-copy fixture instead of
        this repo's real install-project.ps1 (see New-InstallProjectScriptCopy).
    #>
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [string[]]$ExtraArgs = @(),
        [string]$ScriptPath = $script:InstallProjectScriptPath
    )

    $allArgs = @('-NoProfile', '-File', $ScriptPath, '-TargetPath', $TargetPath) + $ExtraArgs
    $output = & pwsh @allArgs 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-ProjectManifestPath {
    param([Parameter(Mandatory)][string]$TargetPath)
    Join-Path $TargetPath $script:StateDirName 'manifest.json'
}

function Get-ProjectStateDir {
    param([Parameter(Mandatory)][string]$TargetPath)
    Join-Path $TargetPath $script:StateDirName
}

function Import-ProjectTestManifest {
    <#
    .SYNOPSIS
        Reads and parses a fixture's manifest.json, or returns $null if it
        does not exist.
    #>
    param([Parameter(Mandatory)][string]$TargetPath)

    $manifestPath = Get-ProjectManifestPath -TargetPath $TargetPath
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Get-InstructionsDir {
    param([Parameter(Mandatory)][string]$TargetPath)
    Join-Path $TargetPath '.github' 'instructions'
}

function Get-Sha256TestFileHash {
    <#
    .SYNOPSIS
        Returns the SHA-256 hex hash of a file's raw bytes, or $null if the
        file does not exist. Test-side mirror of the installer's own
        Get-Sha256FileHash, used only to compute expected values.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-TemplateSourcePath {
    <#
    .SYNOPSIS
        Resolves the repo's real template source file for a given
        -Template variant's project-config file. Mirrors the Template ->
        file-name switch in Test-ProjectInstallPreflight, purely to compute
        expected content for assertions.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('Generic', 'Angular', 'Blazor', 'ServiceFabric')][string]$Template
    )

    $fileName = switch ($Template) {
        'Angular' { 'project-config-angular.instructions.md' }
        'Blazor' { 'project-config-blazor.instructions.md' }
        'ServiceFabric' { 'project-config-service-fabric.instructions.md' }
        default { 'project-config.instructions.md' }
    }
    Join-Path $script:TemplatesDir $fileName
}

function Get-LocalPreferencesSourcePath {
    Join-Path $script:TemplatesDir 'local-preferences.instructions.md'
}
