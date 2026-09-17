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
$script:ProjectFixtureRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:ProjectSuiteRoot = $null
$script:ProjectTestEnvironment = $null

function Initialize-ProjectTestEnvironment {
    # Source freezing adds a nested controlled TEMP; keep fixture paths below legacy Git path limits.
    $script:ProjectSuiteRoot = Join-Path ([IO.Path]::GetTempPath()) ('npcc-ip-' + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $script:ProjectSuiteRoot | Out-Null
    $root = Join-Path $script:ProjectSuiteRoot 'environment'
    $script:ProjectFixtureRoots.Add($root) | Out-Null
    $homePath = Join-Path $root 'home'
    $tempPath = Join-Path $root 'temp'
    $copilotPath = Join-Path $root 'copilot'
    $configPath = Join-Path $root 'empty.gitconfig'
    foreach ($path in @($homePath, $tempPath, $copilotPath, (Join-Path $root 'xdg'), (Join-Path $root 'empty-git-template'),
            (Join-Path $homePath 'AppData\Roaming'), (Join-Path $homePath 'AppData\Local'))) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    [IO.File]::WriteAllText($configPath, '')
    $script:ProjectTestEnvironment = @{
        HOME = $homePath
        USERPROFILE = $homePath
        COPILOT_HOME = $copilotPath
        TEMP = $tempPath
        TMP = $tempPath
        APPDATA = Join-Path $homePath 'AppData\Roaming'
        LOCALAPPDATA = Join-Path $homePath 'AppData\Local'
        XDG_CONFIG_HOME = Join-Path $root 'xdg'
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_CONFIG_GLOBAL = $configPath
        GIT_CONFIG_SYSTEM = $configPath
        GIT_TERMINAL_PROMPT = '0'
        GIT_OPTIONAL_LOCKS = '0'
        GIT_TEMPLATE_DIR = Join-Path $root 'empty-git-template'
        POWERSHELL_TELEMETRY_OPTOUT = '1'
    }
}

function New-ProjectOwnedRoot {
    param([string]$Purpose)
    if (-not $script:ProjectSuiteRoot) { throw 'Initialize the isolated test environment before creating fixtures.' }
    $path = Join-Path $script:ProjectSuiteRoot ($Purpose + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    $script:ProjectFixtureRoots.Add($path) | Out-Null
    $path
}

function Assert-ProjectFixturePath {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $script:ProjectSuiteRoot -or -not $fullPath.StartsWith($script:ProjectSuiteRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not inside this suite's explicitly owned fixtures: '$Path'."
    }
}

function Invoke-ProjectFixtureProcess {
    param(
        [string]$Program,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $script:ProjectSuiteRoot
    )
    Assert-ProjectFixturePath -Path (Join-Path $WorkingDirectory '.fixture-boundary')
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Command $Program -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    foreach ($name in @($info.Environment.Keys)) {
        if ($name -match '^GIT_') { $info.Environment.Remove($name) | Out-Null }
    }
    foreach ($entry in $script:ProjectTestEnvironment.GetEnumerator()) {
        $info.Environment[$entry.Key] = $entry.Value
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "Could not start fixture process '$Program'." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $text + $errorText; Stdout = $text; Stderr = $errorText }
    }
    finally { $process.Dispose() }
}

function Invoke-ProjectFixtureGit {
    param([string]$Root, [string[]]$Arguments)
    Assert-ProjectFixturePath -Path $Root
    Invoke-ProjectFixtureProcess -Program git -Arguments (@('--no-pager', '--no-optional-locks', '-C', $Root,
            '-c', 'core.fsmonitor=false', '-c', 'init.defaultBranch=main') + $Arguments) -WorkingDirectory $Root
}

function New-GitFixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh, empty temp directory initialized as a real git
        repository (via `git init -q`), to use as an isolated -TargetPath.
        Caller is responsible for cleanup.
    #>
    $path = New-ProjectOwnedRoot -Purpose 'repo'
    $git = Invoke-ProjectFixtureGit -Root $path -Arguments @('init', '--quiet')
    if ($git.ExitCode -ne 0) {
        Remove-ProjectFixtureRoot -Path $path
        throw "git init failed for fixture root '$path': $($git.Output)"
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
    New-ProjectOwnedRoot -Purpose 'nongit'
}

function Remove-ProjectFixtureRoot {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    Assert-ProjectFixturePath -Path $resolved
    if (-not $script:ProjectFixtureRoots.Contains($resolved)) { throw "Refusing cleanup of an unregistered fixture root: '$resolved'." }
    if (Test-Path -LiteralPath $resolved) {
        $entry = Get-Item -LiteralPath $resolved -Force
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Fixture root unexpectedly became a link: '$resolved'." }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    $script:ProjectFixtureRoots.Remove($resolved) | Out-Null
}

function Remove-ProjectTestEnvironment {
    foreach ($path in @($script:ProjectFixtureRoots)) { Remove-ProjectFixtureRoot -Path $path }
    if (Test-Path -LiteralPath $script:ProjectSuiteRoot) {
        if (@(Get-ChildItem -LiteralPath $script:ProjectSuiteRoot -Force).Count) {
            throw "Unexpected files remain in suite root '$script:ProjectSuiteRoot'; no broad cleanup was attempted."
        }
        Remove-Item -LiteralPath $script:ProjectSuiteRoot -Force
    }
}

function Get-ProjectTestSourceManifest {
    param([string]$Root = $script:InstallProjectRepoRoot)
    $records = [Collections.Generic.List[object]]::new()
    function Add-SourceEntry {
        param([IO.FileSystemInfo]$Entry)
        if ($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Source snapshot does not follow reparse entries: '$($Entry.FullName)'."
        }
        if ($Entry -is [IO.DirectoryInfo]) {
            foreach ($child in Get-ChildItem -LiteralPath $Entry.FullName -Force) { Add-SourceEntry -Entry $child }
        }
        else {
            $records.Add([pscustomobject]@{ Path = [IO.Path]::GetRelativePath($Root, $Entry.FullName)
                    SHA256 = (Get-FileHash -LiteralPath $Entry.FullName -Algorithm SHA256).Hash })
        }
    }
    foreach ($directory in @($Root, (Join-Path $Root 'tests'), (Join-Path $Root 'tests\InstallProject'))) {
        $entry = Get-Item -LiteralPath $directory -Force
        if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe source directory '$directory'."
        }
    }
    foreach ($relative in @('install-project.ps1', 'tests\InstallProject\Run-InstallProjectTests.ps1',
            'tests\InstallProject\New-InstallProjectFixture.ps1', 'tests\InstallProject\ProjectInstallerSafety.Tests.ps1')) {
        $entry = Get-Item -LiteralPath (Join-Path $Root $relative) -Force
        if ($entry.PSIsContainer) { throw "Expected a source file at '$($entry.FullName)'." }
        Add-SourceEntry -Entry $entry
    }
    $templates = Get-Item -LiteralPath (Join-Path $Root 'templates') -Force
    if (-not $templates.PSIsContainer) { throw 'The template source must be a directory.' }
    Add-SourceEntry -Entry $templates
    $records | Sort-Object Path
}

function Compare-ProjectTestSourceManifest {
    param([array]$Expected, [array]$Actual)
    $before = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $after = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $Expected) {
        $before.Add($record.Path, $record.SHA256)
        $paths.Add($record.Path) | Out-Null
    }
    foreach ($record in $Actual) {
        $after.Add($record.Path, $record.SHA256)
        $paths.Add($record.Path) | Out-Null
    }
    foreach ($path in $paths | Sort-Object) {
        $oldHash = if ($before.ContainsKey($path)) { $before[$path] } else { '[missing]' }
        $newHash = if ($after.ContainsKey($path)) { $after[$path] } else { '[missing]' }
        if ($oldHash -cne $newHash) { [pscustomobject]@{ Path = $path; Before = $oldHash; After = $newHash } }
    }
}

function Get-ProjectTestSourceId {
    param([array]$Files)
    $rows = [string[]]@($Files | ForEach-Object { "$($_.Path)|$($_.SHA256)" })
    [Array]::Sort($rows, [StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($rows -join "`n")))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function New-ProjectFrozenTestSource {
    param([string]$SourceRoot = $script:InstallProjectRepoRoot)
    $before = @(Get-ProjectTestSourceManifest -Root $SourceRoot)
    $root = New-ProjectOwnedRoot -Purpose 'source'
    New-Item -ItemType Directory -Path (Join-Path $root 'templates') | Out-Null
    foreach ($file in $before) {
        $destination = Join-Path $root $file.Path
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        [IO.File]::Copy((Join-Path $SourceRoot $file.Path), $destination, $false)
    }
    $changes = @(Compare-ProjectTestSourceManifest -Expected $before -Actual @(Get-ProjectTestSourceManifest -Root $SourceRoot))
    $copyChanges = @(Compare-ProjectTestSourceManifest -Expected $before -Actual @(Get-ProjectTestSourceManifest -Root $root))
    if ($changes.Count -or $copyChanges.Count) {
        throw "Source changed during snapshot capture. Origin differences: $($changes | ConvertTo-Json -Compress). Copy differences: $($copyChanges | ConvertTo-Json -Compress)."
    }
    $manifest = [pscustomobject]@{ SchemaVersion = 1; SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
        SnapshotRoot = $root; CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
        SourceId = (Get-ProjectTestSourceId -Files $before); Files = $before }
    [IO.File]::WriteAllText((Join-Path $root '.project-test-source.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ Root = $root; RunnerPath = (Join-Path $root 'tests\InstallProject\Run-InstallProjectTests.ps1'); Manifest = $manifest }
}

function Assert-ProjectFrozenTestSource {
    param([string]$Root = $script:InstallProjectRepoRoot)
    $path = Join-Path $Root '.project-test-source.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Frozen execution requires a captured .project-test-source.json; use the normal runner entry point.' }
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($manifest.SchemaVersion -ne 1 -or $manifest.Files -isnot [array] -or
        -not [StringComparer]::OrdinalIgnoreCase.Equals($manifest.SnapshotRoot, [IO.Path]::GetFullPath($Root))) {
        throw 'Invalid or relocated test-source snapshot.'
    }
    $actual = @(Get-ProjectTestSourceManifest -Root $Root)
    $changes = @(Compare-ProjectTestSourceManifest -Expected $manifest.Files -Actual $actual)
    if ($changes.Count -or (Get-ProjectTestSourceId -Files $actual) -cne $manifest.SourceId) {
        throw "Frozen source inputs changed at '$Root': $($changes | ConvertTo-Json -Compress)."
    }
    $manifest
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
    $root = New-ProjectOwnedRoot -Purpose 'scriptcopy'
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
    Assert-ProjectFixturePath -Path $path
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
        [string]$ScriptPath = $script:InstallProjectScriptPath,
        [string]$WorkingDirectory = $script:ProjectSuiteRoot
    )

    Assert-ProjectFixturePath -Path ([IO.Path]::GetFullPath($TargetPath, $WorkingDirectory))
    $allArgs = @('-NoProfile', '-File', $ScriptPath, '-TargetPath', $TargetPath) + $ExtraArgs
    Invoke-ProjectFixtureProcess -Program pwsh -Arguments $allArgs -WorkingDirectory $WorkingDirectory
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

function Assert-ProjectRunSucceeded {
    param($Result)
    if ($Result.ExitCode -ne 0) { throw "Expected exit 0, got $($Result.ExitCode): $($Result.Output)" }
}

function Assert-ProjectRunFailed {
    param($Result, [string]$Pattern)
    if ($Result.ExitCode -eq 0) { throw "Expected a nonzero result: $($Result.Output)" }
    if ($Pattern -and $Result.Output -notmatch $Pattern) { throw "Expected diagnostic '$Pattern': $($Result.Output)" }
}

function Assert-ProjectRootCapabilityReference {
    param([string]$Path)
    Assert-ProjectFixturePath -Path $Path
    $content = [IO.File]::ReadAllText($Path)
    $problems = [Collections.Generic.List[string]]::new()
    if ($content -notmatch '<!-- np-copilot-capabilities-owner: \.github/copilot-instructions.md -->') {
        $problems.Add('missing expected root-owner marker')
    }
    if ($content -notmatch '\[root project contract\]\(\.\./copilot-instructions\.md\)') {
        $problems.Add('reference mismatch: expected the file-only ../copilot-instructions.md link')
    }
    if ($content -match '(?m)^\| Capability \| Enabled \|') { $problems.Add('duplicate capability table') }
    if ($problems.Count) {
        $section = [regex]::Match($content, '(?ms)^## Agent Delivery Capabilities\r?\n.*?(?=^## |\z)').Value
        throw "Capability reference contract failed: $($problems -join '; '). Generated section at '$Path':`n$section"
    }
}

function Save-ProjectTestManifest {
    param([string]$Root, $Manifest)
    Assert-ProjectFixturePath -Path $Root
    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Get-ProjectManifestPath -TargetPath $Root) -Encoding utf8 -NoNewline
}

function Get-ProjectFixtureSnapshot {
    param([string]$Root)
    Assert-ProjectFixturePath -Path $Root
    $entries = [Collections.Generic.List[string]]::new()
    function Read-FixtureDirectory {
        param([string]$Directory)
        foreach ($entry in Get-ChildItem -LiteralPath $Directory -Force | Sort-Object Name) {
            $relative = [IO.Path]::GetRelativePath($Root, $entry.FullName)
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $entries.Add("$relative|link|$($entry.LinkType)|$($entry.Target)")
            }
            elseif ($entry.PSIsContainer) {
                $entries.Add("$relative|directory")
                Read-FixtureDirectory -Directory $entry.FullName
            }
            else {
                $entries.Add("$relative|file|$(Get-Sha256TestFileHash -Path $entry.FullName)")
            }
        }
    }
    Read-FixtureDirectory -Directory $Root
    $entries -join "`n"
}

function Assert-ProjectPrivacy {
    param([string]$Root, [string[]]$BackupPaths = @())
    $paths = @($script:GitignoreEntry, "$script:StateDirName/manifest.json", "$script:StateDirName/backups/.privacy-check")
    if (Test-Path -LiteralPath (Get-ProjectStateDir -TargetPath $Root) -PathType Container) {
        $paths += $script:StateDirName
    }
    $paths += @($BackupPaths | ForEach-Object { [IO.Path]::GetRelativePath($Root, $_).Replace('\', '/') })
    foreach ($path in $paths) {
        $ignored = Invoke-ProjectFixtureGit -Root $Root -Arguments @('check-ignore', '--quiet', '--no-index', '--', $path)
        if ($ignored.ExitCode -ne 0) { throw "Expected actual Git exclusion for '$path': $($ignored.Output)" }
    }
    $untracked = Invoke-ProjectFixtureGit -Root $Root -Arguments @('ls-files', '--others', '--exclude-standard', '-z')
    Assert-ProjectRunSucceeded -Result $untracked
    foreach ($path in @($untracked.Stdout -split "`0" | Where-Object { $_ })) {
        if ($path -ceq $script:GitignoreEntry -or $path.StartsWith("$script:StateDirName/", [StringComparison]::Ordinal)) {
            throw "Private artifact appeared in ordinary untracked output: '$path'."
        }
    }
}

function New-ProjectOriginalFixture {
    param(
        [string]$Name = 'project-config.instructions.md',
        [string]$Original = 'ORIGINAL CONTENT - RESTORE THIS EXACTLY',
        [string]$ScriptPath = $script:InstallProjectScriptPath
    )
    $root = New-GitFixtureRoot
    $directory = Get-InstructionsDir -TargetPath $root
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Join-Path $directory $Name
    Set-Content -LiteralPath $path -Value $Original -Encoding utf8 -NoNewline
    $hash = Get-Sha256TestFileHash -Path $path
    Assert-ProjectRunSucceeded -Result (Invoke-InstallProject -TargetPath $root -ScriptPath $ScriptPath -ExtraArgs @('-Force'))
    $manifest = Import-ProjectTestManifest -TargetPath $root
    $artifact = @($manifest.Artifacts | Where-Object Name -CEQ $Name)[0]
    if (-not $artifact.BackupPath -or (Get-Sha256TestFileHash -Path $artifact.BackupPath) -cne $hash) {
        throw 'Fixture Force install failed to preserve its original.'
    }
    [pscustomobject]@{ Root = $root; Path = $path; OriginalHash = $hash; BackupPath = $artifact.BackupPath
        ManifestPath = (Get-ProjectManifestPath -TargetPath $root) }
}
