#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FixtureRoot, [Parameter(Mandatory)][string]$ScenarioPath)

$ErrorActionPreference = 'Stop'
$config = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($ScenarioPath)) -AsHashtable
$source = Join-Path $FixtureRoot "source O'Brien [1];`$literal"
$target = Join-Path $FixtureRoot "target O'Brien [2];`$literal"
function Start-DeployProcess {
        param(
            [string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory,
            [byte[]]$InputBytes, [string[]]$RemoveEnvironment = @(),
            [int]$TimeoutMilliseconds, [string]$Description
        )
        $script:FixtureRoot = Split-Path $PSScriptRoot -Parent
        $script:FixtureTarget = Join-Path $script:FixtureRoot "target O'Brien [2];`$literal"
        $script:FixtureConfig = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((Join-Path $script:FixtureRoot 'scenario.json'))) -AsHashtable
        if (-not (Get-Variable -Name ReadinessIndex -Scope Script -ErrorAction SilentlyContinue)) { $script:ReadinessIndex = 0 }
        if ($FilePath -notin @('docker', 'ssh', 'wsl.exe')) { throw "Unexpected native executable: $FilePath" }
        $hash = ''
        if ($null -ne $InputBytes) {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $hash = [System.BitConverter]::ToString($sha.ComputeHash($InputBytes)).Replace('-', '') }
            finally { $sha.Dispose() }
        }
        $record = @{
            FilePath = $FilePath; ArgumentList = @($ArgumentList); WorkingDirectory = $WorkingDirectory
            Description = $Description; TimeoutMilliseconds = $TimeoutMilliseconds
            RemoveEnvironment = @($RemoveEnvironment); InputHash = $hash
        }
        Add-Content -LiteralPath (Join-Path $script:FixtureRoot 'native-calls.jsonl') -Value (ConvertTo-Json -InputObject $record -Compress -Depth 6)
        $config = $script:FixtureConfig
        if ($config['FailOperation'] -eq $Description) {
            return [pscustomobject]@{ ExitCode = 47; Output = $config.EffectiveSecret; TimedOut = $false }
        }
        if ($config['TimeoutOperation'] -eq $Description) {
            return [pscustomobject]@{ ExitCode = $null; Output = ''; TimedOut = $true }
        }
        if ($config['NullStatusOperation'] -eq $Description) {
            return [pscustomobject]@{ ExitCode = $null; Output = ''; TimedOut = $false }
        }
        $output = switch ($Description) {
            'Resolve target directory' { $config.ResolvedPath }
            'Inspect deployed Compose file' {
                if (Test-Path -LiteralPath (Join-Path $script:FixtureTarget 'mcps.docker-compose.yml')) { "present`n" } else { "missing`n" }
            }
            'Inspect deployed settings' {
                if (Test-Path -LiteralPath (Join-Path $script:FixtureTarget 'searxng\settings.yml')) { "present`n" } else { "missing`n" }
            }
            'Inspect deployed .env' {
                $envPath = Join-Path $script:FixtureTarget '.env'
                if (Test-Path -LiteralPath $envPath) { "present`n" + [System.IO.File]::ReadAllText($envPath) } else { "missing`n" }
            }
            'Validate deployed Compose configuration' {
                if ($config['InvalidComposeJson']) { '{ invalid JSON ' + $config.EffectiveSecret; break }
                $environment = @{ SEARXNG_SECRET = $config.EffectiveSecret; SEARXNG_BASE_URL = 'http://raspberrypi:8080/' }
                if ($config['MissingSecretMapping']) { $environment.Remove('SEARXNG_SECRET') }
                if ($config['ForwardHostPort']) { $environment['SEARXNG_PORT'] = '9080' }
                $service = @{ environment = $environment }
                if ($config['GlobalContainerName']) { $service['container_name'] = 'searxng' }
                $networkName = if ($config['GlobalNetworkName']) { 'mcp-network' } else { $config.Project + '_mcp-network' }
                ConvertTo-Json -InputObject @{
                    name = $config.Project; services = @{ searxng = $service }
                    networks = @{ 'mcp-network' = @{ name = $networkName } }
                } -Depth 6 -Compress
            }
            'Read SearXNG readiness' {
                $index = [Math]::Min($script:ReadinessIndex, $config.Statuses.Count - 1)
                $state = $config.Statuses[$index]
                $script:ReadinessIndex++
                switch ($state) {
                    'healthy' { '[{"Service":"searxng","State":"running","Health":"healthy"}]' }
                    'starting' { '[{"Service":"searxng","State":"running","Health":"starting"}]' }
                    'unhealthy' { '[{"Service":"searxng","State":"running","Health":"unhealthy"}]' }
                    'exited' { '[{"Service":"searxng","State":"exited","Health":"","ExitCode":1}]' }
                    'missing' { '[]' }
                    'empty' { '' }
                    'no-health' { '[{"Service":"searxng","State":"running"}]' }
                    'no-healthcheck' { '[{"Service":"searxng","State":"running","Health":""}]' }
                    'malformed' { 'this is not JSON' }
                    'duplicate' { '[{"Service":"searxng","State":"running","Health":"healthy"},{"Service":"searxng","State":"running","Health":"healthy"}]' }
                    'ndjson' { "{`"Service`":`"other`",`"State`":`"exited`",`"Health`":`"`"}`n{`"Service`":`"searxng`",`"State`":`"running`",`"Health`":`"healthy`"}`n" }
                    default { throw 'Unexpected readiness fixture.' }
                }
            }
            { $_ -in @('Prepare target directory', 'Publish Compose file', 'Publish SearXNG settings', 'Publish private .env',
                    'Reset private .env', 'Pull pinned SearXNG image', 'Start SearXNG',
                    'Validate private environment permissions (owner, mode 600/400)') } { '' }
            default { throw "Unexpected native operation: $Description" }
        }
        [pscustomobject]@{ ExitCode = 0; Output = [string]$output; TimedOut = $false }
}

# Replace only the native-process boundary in this disposable module copy.
# Importing an entry point in a new script scope must not evade interception.
$modulePath = Join-Path $source 'Mcp.Deployment.psm1'
$tokens = $null
$errors = $null
$moduleAst = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Deployment module fixture has parse errors.' }
$original = @($moduleAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-DeployProcess' }, $true))
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Native interception fixture has parse errors.' }
$replacement = @($runnerAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-DeployProcess' }, $true))
if ($original.Count -ne 1 -or $replacement.Count -ne 1) { throw 'Expected exactly one native-process interception boundary.' }
$text = [System.IO.File]::ReadAllText($modulePath)
$text = $text.Substring(0, $original[0].Extent.StartOffset) + $replacement[0].Extent.Text + $text.Substring($original[0].Extent.EndOffset)
[System.IO.File]::WriteAllText($modulePath, $text, [System.Text.UTF8Encoding]::new($false))

$global:LASTEXITCODE = $config.InitialStatus
function global:wslpath {
    [System.IO.File]::WriteAllText((Join-Path $FixtureRoot 'host-wslpath-called'), 'Host evaluation is forbidden.')
    throw 'wslpath was evaluated in host PowerShell.'
}

try {
    $entry = if ($config.Operation -eq 'initialize') { 'Initialize-Environment.ps1' } else { 'deploy.ps1' }
    $parameters = $config.Parameters
    & (Join-Path $source $entry) @parameters
    $entrySucceeded = $?
    $entryExitCode = if ($entrySucceeded) { 0 } elseif ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
}
finally {
    [System.IO.File]::WriteAllText((Join-Path $FixtureRoot 'last-native-status.json'), (ConvertTo-Json -InputObject $global:LASTEXITCODE -Compress))
}
exit $entryExitCode
