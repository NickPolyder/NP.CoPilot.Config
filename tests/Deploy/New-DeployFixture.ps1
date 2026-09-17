#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$script:DeployRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:DeployFixtureRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:FixtureKey = '0123456789abcdef' * 4
$script:AlternateFixtureKey = 'fedcba9876543210' * 4
$script:DeploySourceFiles = @('deploy.ps1', 'Initialize-Environment.ps1', 'Mcp.Deployment.psm1', 'docker-compose.yml', '.env.example', 'searxng\settings.yml')

function Get-FixtureEnvironment {
    param([string]$Key = $script:FixtureKey, [int]$Port = 8080, [string]$Hostname = 'raspberrypi')
    # Public deterministic test data, never a credential for a running service.
    "SEARXNG_HOSTNAME=$Hostname`nSEARXNG_PORT=$Port`nSEARXNG_SECRET=$Key`n"
}

function Set-FixturePrivateFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [System.Security.AccessControl.FileSecurity]::new()
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function New-DeployFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('npcc-deploy-test-' + [guid]::NewGuid().ToString('N'))
    $null = [System.IO.Directory]::CreateDirectory($root)
    $null = $script:DeployFixtureRoots.Add($root)
    try {
        $source = Join-Path $root "source O'Brien [1];`$literal"
        $target = Join-Path $root "target O'Brien [2];`$literal"
        $null = [System.IO.Directory]::CreateDirectory((Join-Path $source 'searxng'))
        foreach ($relative in $script:DeploySourceFiles) {
            Copy-Item -LiteralPath (Join-Path $script:DeployRepoRoot 'mcps' $relative) -Destination (Join-Path $source $relative)
        }
        Set-FixturePrivateFile -Path (Join-Path $source '.env') -Content (Get-FixtureEnvironment)
        foreach ($name in @('docker.exe', 'ssh.exe', 'wsl.exe')) {
            [System.IO.File]::WriteAllText((Join-Path $root $name), 'Not an executable: a deployment test must intercept this command.')
        }
        [pscustomobject]@{
            Root = $root; Source = $source; Target = $target
            Log = (Join-Path $root 'native-calls.jsonl')
            StatusFile = (Join-Path $root 'last-native-status.json')
        }
    }
    catch {
        Remove-DeployFixture -Path $root
        throw
    }
}

function Remove-DeployFixture {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $script:DeployFixtureRoots.Contains($full) -or
        (Split-Path $full -Parent) -ne $temp -or (Split-Path $full -Leaf) -notmatch '^npcc-deploy-test-[0-9a-f]{32}$') {
        throw "Refusing cleanup of an unowned fixture: $full"
    }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Fixture root became a link: $full" }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    if (Test-Path -LiteralPath $full) { throw "Fixture cleanup did not finish: $full" }
    $null = $script:DeployFixtureRoots.Remove($full)
}

function Initialize-DeployedFixture {
    param($Fixture, [string]$Environment = (Get-FixtureEnvironment), [string]$ComposeFile = 'mcps.docker-compose.yml')
    $null = [System.IO.Directory]::CreateDirectory((Join-Path $Fixture.Target 'searxng'))
    Copy-Item -LiteralPath (Join-Path $Fixture.Source 'docker-compose.yml') -Destination (Join-Path $Fixture.Target $ComposeFile)
    Copy-Item -LiteralPath (Join-Path $Fixture.Source 'searxng\settings.yml') -Destination (Join-Path $Fixture.Target 'searxng\settings.yml')
    Set-FixturePrivateFile -Path (Join-Path $Fixture.Target '.env') -Content $Environment
}

function Invoke-FixtureProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{},
        [string[]]$RemoveEnvironment = @()
    )
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $WorkingDirectory
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add($argument) }
    foreach ($name in $RemoveEnvironment) { $null = $start.Environment.Remove($name) }
    foreach ($name in $Environment.Keys) { $start.Environment[$name] = $Environment[$name] }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Isolated fixture process exceeded 30 seconds.'
        }
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult()
            Error = $stderr.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Invoke-DeployFixture {
    param(
        $Fixture,
        [hashtable]$Parameters = @{},
        [hashtable]$Scenario = @{},
        [ValidateSet('deploy', 'initialize')][string]$Operation = 'deploy'
    )
    if (Test-Path -LiteralPath $Fixture.Log) { Remove-Item -LiteralPath $Fixture.Log }
    $arguments = if ($Operation -eq 'deploy') {
        @{ DeployMode = 'Local'; RemotePath = $Fixture.Target; ReadinessTimeoutSeconds = 3; ReadinessPollSeconds = 1 }
    }
    else { @{} }
    foreach ($key in $Parameters.Keys) { $arguments[$key] = $Parameters[$key] }
    $config = @{
        Parameters = $arguments; Operation = $Operation; EffectiveSecret = $script:FixtureKey
        ResolvedPath = "/home/test O'Brien/DockerScripts/stack [1];`$literal"
        InitialStatus = $null; Statuses = @('healthy')
        Project = 'np-copilot-mcp'
    }
    foreach ($key in $Scenario.Keys) { $config[$key] = $Scenario[$key] }
    $scenarioPath = Join-Path $Fixture.Root 'scenario.json'
    [System.IO.File]::WriteAllText($scenarioPath, (ConvertTo-Json -InputObject $config -Depth 10), [System.Text.UTF8Encoding]::new($false))
    $result = Invoke-FixtureProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'Invoke-DeployFixture.ps1'),
            '-FixtureRoot', $Fixture.Root, '-ScenarioPath', $scenarioPath) -WorkingDirectory $Fixture.Root `
        -Environment @{ PATH = $Fixture.Root; COPILOT_HOME = (Join-Path $Fixture.Root 'unused-home') }
    $calls = if (Test-Path -LiteralPath $Fixture.Log) {
        @(Get-Content -LiteralPath $Fixture.Log | ForEach-Object { ConvertFrom-Json -InputObject $_ })
    }
    else { @() }
    [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output + $result.Error; Calls = @($calls) }
}

function Invoke-FixtureModule {
    param($Fixture, [scriptblock]$Script, [object[]]$ArgumentList = @())
    $module = Import-Module (Join-Path $Fixture.Source 'Mcp.Deployment.psm1') -PassThru
    try { & $module $Script @ArgumentList }
    finally { Remove-Module -ModuleInfo $module -Force }
}

function Get-FixtureHash {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-PosixTokens {
    param([string]$Command, $Fixture)
    $script = 'set -- ' + $Command + '; printf ''%s\0'' "$@"'
    $result = Invoke-FixtureProcess -FilePath $script:GitBash -ArgumentList @('--noprofile', '--norc', '-c', $script) `
        -WorkingDirectory $Fixture.Root -RemoveEnvironment @('BASH_ENV', 'ENV', 'SHELLOPTS', 'BASHOPTS')
    if ($result.ExitCode -ne 0) { throw 'Git Bash could not parse the transported SSH arguments.' }
    $result.Output.TrimEnd([char]0).Split([char]0)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Arguments {
    param([object[]]$Actual, [object[]]$Expected, [string]$Message)
    if ((ConvertTo-Json -InputObject @($Actual) -Compress) -cne (ConvertTo-Json -InputObject @($Expected) -Compress)) {
        throw "$Message (argument values withheld)"
    }
}

function Assert-DeploySucceeded {
    param($Result)
    Assert-True ($Result.ExitCode -eq 0) "Expected exit 0. $($Result.Output)"
    Assert-True ($Result.Output.Contains('MCP stack is ready (SearXNG healthy).')) 'Missing health-qualified ready banner.'
    Assert-True (-not $Result.Output.Contains($script:FixtureKey)) 'Fixture key leaked into deployment output.'
    Assert-True (-not $Result.Output.Contains($script:AlternateFixtureKey)) 'Alternate fixture key leaked into deployment output.'
}

function Assert-DeployFailed {
    param($Result, [string]$Pattern)
    Assert-True ($Result.ExitCode -ne 0) 'Expected a nonzero deployment failure.'
    Assert-True ($Result.Output -match $Pattern) "Missing expected failure diagnostic: $Pattern. $($Result.Output)"
    Assert-True (-not $Result.Output.Contains('MCP stack is ready')) 'Failed deployment announced readiness.'
    Assert-True (-not $Result.Output.Contains($script:FixtureKey)) 'Fixture key leaked into failure output.'
    Assert-True (-not $Result.Output.Contains($script:AlternateFixtureKey)) 'Alternate fixture key leaked into failure output.'
}
