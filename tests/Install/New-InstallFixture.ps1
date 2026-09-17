#Requires -Version 7.0
<#
.SYNOPSIS
    Builds isolated, disposable fixture trees and invocation helpers for
    install.ps1 tests.
.DESCRIPTION
    No side effects outside $env:TEMP. Every helper here only ever writes to
    a caller-supplied fixture root; none of them touch the repository's real
    ~/.copilot. install.ps1 itself is never modified — it is only invoked
    out-of-process with -TargetRoot pointed at a disposable temp directory.
    Callers must remove the returned fixture root when done
    (Remove-FixtureRoot / try-finally).
#>

$ErrorActionPreference = 'Stop'

# tests\Install\New-InstallFixture.ps1 -> repo root is two levels up.
$script:InstallRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:InstallScriptPath = Join-Path $script:InstallRepoRoot 'install.ps1'
$script:InstallFixtureRoots = [System.Collections.Generic.List[string]]::new()
$script:IsolatedInstallInvocations = 0

function New-FixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory to use as an isolated
        -TargetRoot. Caller is responsible for cleanup.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-install-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null
    $script:InstallFixtureRoots.Add($path)
    $path
}

function Remove-FixtureRoot {
    param([Parameter(Mandatory)][string]$Path)

    if (-not $script:InstallFixtureRoots.Contains($Path)) { throw "Refusing cleanup of an unowned fixture: $Path" }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Invoke-Install {
    <#
    .SYNOPSIS
        Runs install.ps1 out-of-process against an isolated -TargetRoot.
        Returns exit code + combined stdout/stderr.
    .PARAMETER InstallScriptPath
        Defaults to this repository's real install.ps1. Tests that must
        simulate a tracked source revision (a change to the repo's own
        mcp-config.json) pass the install.ps1 belonging to an isolated
        source root built by New-IsolatedSourceRoot instead, so the real
        repository source is never touched.
    #>
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [string[]]$ExtraArgs = @(),
        [string]$InstallScriptPath = $script:InstallScriptPath,
        [string]$WorkingDirectory = $script:InstallRepoRoot,
        [hashtable]$Environment = @{},
        [switch]$UseDefaultTarget
    )

    $control = New-FixtureRoot
    $fixtureHome = Join-Path $control 'home'
    $temp = Join-Path $control 'temp'
    New-Item -ItemType Directory -Path $fixtureHome, $temp | Out-Null
    $config = Join-Path $control 'empty.gitconfig'
    Set-Content -LiteralPath $config -Value '' -NoNewline
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($name in @($start.Environment.Keys)) {
        if ($name -like 'GIT_*') { [void]$start.Environment.Remove($name) }
    }
    foreach ($name in @('HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME')) {
        $start.Environment[$name] = $fixtureHome
    }
    foreach ($name in @('TEMP', 'TMP', 'TMPDIR')) { $start.Environment[$name] = $temp }
    $start.Environment['COPILOT_HOME'] = Join-Path $fixtureHome '.copilot'
    $start.Environment['GIT_CONFIG_GLOBAL'] = $config
    $start.Environment['GIT_CONFIG_SYSTEM'] = $config
    $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { [void]$start.Environment.Remove($name) }
        else { $start.Environment[$name] = [string]$Environment[$name] }
    }
    $selectedTarget = if ($UseDefaultTarget) {
        if ([string]::IsNullOrWhiteSpace($start.Environment['COPILOT_HOME'])) { Join-Path $start.Environment['USERPROFILE'] '.copilot' }
        else { $start.Environment['COPILOT_HOME'] }
    }
    else { $TargetRoot }
    foreach ($path in @($selectedTarget, $start.Environment['HOME'], $start.Environment['USERPROFILE'])) {
        $fullPath = [System.IO.Path]::GetFullPath($path, $WorkingDirectory)
        $owned = @($script:InstallFixtureRoots | Where-Object {
            $fullPath -eq $_ -or $fullPath.StartsWith($_ + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($owned.Count -eq 0) { throw "Installer test attempted to select an unowned home/target: $fullPath" }
    }
    $allArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $InstallScriptPath)
    if (-not $UseDefaultTarget) { $allArgs += @('-TargetRoot', $TargetRoot) }
    $allArgs += $ExtraArgs
    foreach ($argument in $allArgs) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            Stop-Process -Id $process.Id -Force
            throw 'Isolated installer invocation timed out.'
        }
        $script:IsolatedInstallInvocations++
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    }
    finally {
        $process.Dispose()
        Remove-FixtureRoot $control
    }
}

function New-IsolatedSourceRoot {
    <#
    .SYNOPSIS
        Copies install.ps1 and the minimal source tree it reads (the four
        core link sources + mcp-config.json) into a fresh, disposable temp
        directory. Caller is responsible for cleanup.
    .DESCRIPTION
        install.ps1 resolves its own "$source" as $PSScriptRoot, which is
        wherever the physical script file lives — there is no parameter
        seam for source content the way -TargetRoot is a seam for the
        target. Simulating a tracked source revision (e.g. this repo's
        mcp-config.json gaining a new/changed entry between installs)
        therefore requires running an unmodified *copy* of install.ps1
        from a separate temp location whose own copy of mcp-config.json a
        test can freely mutate, so the real repository source is never
        touched. This is read-only with respect to the real repo: every
        file is only ever copied out, never written back.
    #>
    $isolatedRoot = New-FixtureRoot

    Copy-Item -LiteralPath $script:InstallScriptPath -Destination (Join-Path $isolatedRoot 'install.ps1') -Force

    foreach ($name in (@($script:CoreLinkNames) + @('mcp-config.json'))) {
        $sourcePath = Get-RepoSourcePath $name
        $destinationPath = Join-Path $isolatedRoot $name
        if (Test-Path -LiteralPath $sourcePath -PathType Container) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
    }

    $isolatedRoot
}

function Get-McpServerNames {
    <#
    .SYNOPSIS
        Reads any mcp-config.json's top-level mcpServers key names. Used
        both for the real repo source (Get-RepoMcpServerNames) and for an
        isolated source-root copy that a test has revised.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $json = $raw | ConvertFrom-Json
    @($json.mcpServers.PSObject.Properties.Name)
}

function Get-ManifestPath {
    param([Parameter(Mandatory)][string]$TargetRoot)
    Join-Path $TargetRoot '.np-copilot-installer\manifest.json'
}

function Import-Manifest {
    <#
    .SYNOPSIS
        Reads and parses a fixture's manifest.json, or returns $null if it
        does not exist.
    #>
    param([Parameter(Mandatory)][string]$TargetRoot)

    $manifestPath = Get-ManifestPath -TargetRoot $TargetRoot
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Resolve-TestLinkTarget {
    <#
    .SYNOPSIS
        Test-only mirror of install.ps1's link-target resolution, used
        purely to compute expected values for assertions. Never used by
        the system under test itself.
    #>
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)

    if ($Item.LinkType -ne 'SymbolicLink' -or -not $Item.Target) { return $null }
    $rawTarget = @($Item.Target)[0]
    if ([System.IO.Path]::IsPathRooted($rawTarget)) {
        return [System.IO.Path]::GetFullPath($rawTarget)
    }
    return [System.IO.Path]::GetFullPath($rawTarget, (Split-Path $Item.FullName -Parent))
}

function Test-IsSymlinkTo {
    <#
    .SYNOPSIS
        Returns $true only if Path exists, is a symbolic link, and resolves
        to ExpectedTarget.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedTarget
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType -ne 'SymbolicLink') { return $false }
    (Resolve-TestLinkTarget $item) -eq $ExpectedTarget
}

function Get-RepoSourcePath {
    param([Parameter(Mandatory)][string]$Name)
    Join-Path $script:InstallRepoRoot $Name
}

function Get-RepoMcpServerNames {
    <#
    .SYNOPSIS
        Reads the repo's actual mcp-config.json (never modified by tests)
        and returns its current top-level mcpServers key names, so merge
        assertions stay correct even if that file's contents change later.
    #>
    Get-McpServerNames -Path (Get-RepoSourcePath 'mcp-config.json')
}

$script:CoreLinkNames = @('copilot-instructions.md', 'instructions', 'agents', 'skills')
