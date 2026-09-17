#Requires -Version 7.0
<#
.SYNOPSIS
    Dependency-free, isolated Windows regression suite for MCP deployment.
.DESCRIPTION
    Copies only named deployment inputs into owned temporary fixtures.
    Deployment entry points run in child PowerShell processes whose native
    boundary is replaced with a fail-closed recorder. No SSH/WSL/Docker service
    starts, home mutations, Git mutations, downloads or Pester dependencies.
    Available Git Bash executes local argument/copy probes, never WSL.
    Available Docker Compose performs read-only config parsing with nonsecret input.
.EXAMPLE
    pwsh -NoProfile -File .\tests\Deploy\Run-DeployTests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This suite validates Windows native/SSH/WSL launch boundaries; run it in PowerShell 7+ on Windows.' }
. (Join-Path $PSScriptRoot 'New-DeployFixture.ps1')
. (Join-Path $PSScriptRoot 'InheritedOutput.Cases.ps1')
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
$script:GitBash = if ($git) { Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'bin\bash.exe' } else { '' }
$hasGitBash = $script:GitBash -and (Test-Path -LiteralPath $script:GitBash -PathType Leaf)
$docker = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue
$guardPaths = @($script:DeploySourceFiles | ForEach-Object { Join-Path $script:DeployRepoRoot 'mcps' $_ }) +
    @((Join-Path $script:DeployRepoRoot 'mcp-config.json'), (Join-Path $script:DeployRepoRoot 'prompts\Improve-yourself.prompt.md'))
$before = @{}
foreach ($path in $guardPaths) { $before[$path] = Get-FixtureHash $path }

function Test-Case {
    param([string]$Name, [scriptblock]$Test, [switch]$Skip)
    if ($Skip) {
        $script:TestsSkipped++
        Write-Host "  SKIP $Name (optional local parser unavailable)" -ForegroundColor Yellow
        return
    }
    $fixture = $null
    try {
        $fixture = New-DeployFixture
        & $Test $fixture
        $script:TestsPassed++
        Write-Host "  PASS $Name" -ForegroundColor Green
    }
    catch {
        $script:TestsFailed++
        Write-Host "  FAIL $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($fixture) {
            try { Remove-DeployFixture -Path $fixture.Root }
            catch {
                $script:TestsFailed++
                Write-Host "  FAIL cleanup: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`nMCP deployment regression suite (no live deployment)" -ForegroundColor Cyan

foreach ($status in @($null, 0, 71)) {
    Test-Case "Local directory/copy succeeds with inherited LASTEXITCODE=$status" {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ InitialStatus = $status }
        Assert-DeploySucceeded $result
        foreach ($pair in @(@('docker-compose.yml', 'mcps.docker-compose.yml'), @('searxng\settings.yml', 'searxng\settings.yml'), @('.env', '.env'))) {
            Assert-True ((Get-FixtureHash (Join-Path $fixture.Source $pair[0])) -eq (Get-FixtureHash (Join-Path $fixture.Target $pair[1]))) 'Published bytes differ from the source.'
        }
        $after = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($fixture.StatusFile))
        Assert-True ($after -eq $status) 'Deployment globally reset inherited LASTEXITCODE.'
    }
}

Test-Case 'Local literal arguments preserve spaces, apostrophes, brackets, dollars and custom Compose filename' {
    param($fixture)
    $name = "team's compose [x];`$file.yml"
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ ComposeFile = $name; ProjectName = 'isolated-search-2' } -Scenario @{ Project = 'isolated-search-2' }
    Assert-DeploySucceeded $result
    $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
    Assert-Arguments $up.ArgumentList @('compose', '--project-name', 'isolated-search-2', '--project-directory', $fixture.Target,
        '--env-file', (Join-Path $fixture.Target '.env'), '-f', (Join-Path $fixture.Target $name),
        'up', '-d', '--no-deps', '--force-recreate', 'searxng') 'Local Docker argv was reinterpreted.'
    Assert-True ($up.WorkingDirectory -eq $fixture.Target) 'Compose did not use the deployment directory.'
    Assert-True ($up.RemoveEnvironment -contains 'SEARXNG_PORT' -and $up.RemoveEnvironment -contains 'SEARXNG_SECRET') 'Inherited input overrides were not removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Target $name) -PathType Leaf) 'Custom target filename was not created literally.'
}

Test-Case 'Cmdlet directory failure stops before all Docker commands and preserves the blocking file' {
    param($fixture)
    $null = [System.IO.Directory]::CreateDirectory($fixture.Target)
    $block = Join-Path $fixture.Target 'searxng'
    [System.IO.File]::WriteAllText($block, 'do not replace this file')
    $hash = Get-FixtureHash $block
    $result = Invoke-DeployFixture $fixture
    Assert-DeployFailed $result 'exist|directory|file'
    Assert-True ($result.Calls.Count -eq 0) 'Docker was called after a cmdlet failure.'
    Assert-True ((Get-FixtureHash $block) -eq $hash) 'Blocking file was changed.'
}

Test-Case 'Copy failure stops without pull/up or a success-shaped fallback' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    $path = Join-Path $fixture.Target 'mcps.docker-compose.yml'
    $hash = Get-FixtureHash $path
    $lock = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
    try { $result = Invoke-DeployFixture $fixture }
    finally { $lock.Dispose() }
    Assert-DeployFailed $result 'process|access|used|copy'
    Assert-True ($result.Calls.Count -eq 0) 'Docker was called after a copy failure.'
    Assert-True ((Get-FixtureHash $path) -eq $hash) 'Locked destination was modified.'
}

foreach ($operation in @('Validate deployed Compose configuration', 'Pull pinned SearXNG image', 'Start SearXNG', 'Read SearXNG readiness')) {
    Test-Case "Native failure propagates exit 47 and stops after $operation" {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ FailOperation = $operation }
        Assert-DeployFailed $result 'native exit 47'
        Assert-True ($result.ExitCode -eq 47) 'The entry script lost the native exit code.'
        Assert-True ($result.Calls[-1].Description -eq $operation) 'A subsequent phase ran after native failure.'
    }
}

Test-Case 'A timed-out native command returns failure, not a ready banner' {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ TimeoutOperation = 'Start SearXNG' }
    Assert-DeployFailed $result 'timed out'
    Assert-True ($result.ExitCode -eq 124) 'Native timeout exit status was lost.'
    Assert-True ($result.Calls[-1].Description -eq 'Start SearXNG') 'Readiness ran after native startup timeout.'
}

Test-Case 'Missing actual native exit status fails closed (unlike irrelevant inherited LASTEXITCODE)' {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ NullStatusOperation = 'Pull pinned SearXNG image' }
    Assert-DeployFailed $result 'did not return a native exit status'
    Assert-True ($result.Calls[-1].Description -eq 'Pull pinned SearXNG image') 'Startup ran without a native status.'
}

foreach ($mode in @('Remote', 'WSL')) {
    Test-Case "$mode transfer failure preserves native status and stops before pull/up" {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = $mode; RemotePath = '~/DockerScripts' } `
            -Scenario @{ FailOperation = 'Publish SearXNG settings' }
        Assert-DeployFailed $result 'native exit 47'
        Assert-True ($result.ExitCode -eq 47 -and $result.Calls[-1].Description -eq 'Publish SearXNG settings') 'Transfer failure did not stop subsequent phases.'
        Assert-True (@($result.Calls | Where-Object Description -eq 'Pull pinned SearXNG image').Count -eq 0) 'A partial publication proceeded to pull.'
    }
}

foreach ($relative in @('docker-compose.yml', 'searxng\settings.yml')) {
    Test-Case "Missing required source $relative fails before any target calls or creation" {
        param($fixture)
        Remove-Item -LiteralPath (Join-Path $fixture.Source $relative)
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = 'Remote'; RemotePath = '~/DockerScripts' }
        Assert-DeployFailed $result 'Required source input is missing'
        Assert-True ($result.Calls.Count -eq 0) 'Missing source reached a target command.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Missing source created the target.'
    }
}

foreach ($relative in @('mcps.docker-compose.yml', 'searxng\settings.yml', '.env')) {
    Test-Case "SkipCopy rejects missing deployed $relative without starting containers" {
        param($fixture)
        Initialize-DeployedFixture $fixture
        Remove-Item -LiteralPath (Join-Path $fixture.Target $relative)
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ SkipCopy = $true }
        Assert-DeployFailed $result 'SkipCopy requires deployed'
        Assert-True ($result.Calls.Count -eq 0) 'SkipCopy continued after missing deployed input.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Target $relative))) 'SkipCopy recreated a missing input.'
    }
}

Test-Case 'SkipCopy uses complete deployed inputs even when required source inputs are absent' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    Remove-Item -LiteralPath (Join-Path $fixture.Source 'docker-compose.yml'), (Join-Path $fixture.Source 'searxng\settings.yml'), (Join-Path $fixture.Source '.env')
    $hash = Get-FixtureHash (Join-Path $fixture.Target '.env')
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ SkipCopy = $true }
    Assert-DeploySucceeded $result
    $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
    Assert-True ($up.ArgumentList -notcontains '--force-recreate') 'SkipCopy claimed an unchanged deployment but forced restart.'
    Assert-True ((Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq $hash) 'SkipCopy changed target environment bytes.'
}

Test-Case 'Settings-only update is published before forced recreation; unchanged deployment also follows that policy' {
    param($fixture)
    Assert-DeploySucceeded (Invoke-DeployFixture $fixture)
    $path = Join-Path $fixture.Source 'searxng\settings.yml'
    $content = [System.IO.File]::ReadAllText($path).Replace('SearXNG MCP', 'SearXNG MCP isolated reload fixture')
    [System.IO.File]::WriteAllText($path, $content)
    foreach ($run in @(1, 2)) {
        $result = Invoke-DeployFixture $fixture
        Assert-DeploySucceeded $result
        Assert-True ((Get-FixtureHash $path) -eq (Get-FixtureHash (Join-Path $fixture.Target 'searxng\settings.yml'))) 'Settings-only edit did not reach the deployed input.'
        $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
        Assert-True ($up.ArgumentList -contains '--force-recreate') 'Normal deployment did not reload bind-mounted settings.'
    }
}

Test-Case 'Explicit SkipCopy Restart forces recreation without copying edited source settings' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    $before = Get-FixtureHash (Join-Path $fixture.Target 'searxng\settings.yml')
    [System.IO.File]::AppendAllText((Join-Path $fixture.Source 'searxng\settings.yml'), "`n# source-only fixture change`n")
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ SkipCopy = $true; Restart = $true }
    Assert-DeploySucceeded $result
    $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
    Assert-True ($up.ArgumentList -contains '--force-recreate') 'Explicit restart did not request actual recreation.'
    Assert-True ((Get-FixtureHash (Join-Path $fixture.Target 'searxng\settings.yml')) -eq $before) 'Restart unexpectedly copied source settings.'
}

foreach ($invalid in @('', 'CHANGE_ME_TO_A_RANDOM_SECRET', 'ultrasecretkey', ('0' * 64), 'short', ($script:FixtureKey + '0'), '${OTHER_SECRET}')) {
    $label = if ($invalid.Length -eq 0) { 'empty' } else { "invalid length/content $($invalid.Length)" }
    Test-Case "Source secret validation rejects $label before target mutation" {
        param($fixture)
        Set-FixturePrivateFile -Path (Join-Path $fixture.Source '.env') -Content (Get-FixtureEnvironment -Key $invalid)
        $result = Invoke-DeployFixture $fixture
        Assert-DeployFailed $result 'requires SEARXNG_SECRET'
        Assert-True ($result.Calls.Count -eq 0 -and -not (Test-Path -LiteralPath $fixture.Target)) 'Invalid key reached mutation.'
    }
}

foreach ($content in @(
        ((Get-FixtureEnvironment) + "export SEARXNG_SECRET=$script:AlternateFixtureKey`n"),
        ((Get-FixtureEnvironment) + "SEARXNG_PORT=9080`n"),
        ((Get-FixtureEnvironment) -replace 'SEARXNG_PORT=8080', 'SEARXNG_PORT=65536'),
        ((Get-FixtureEnvironment) -replace 'SEARXNG_HOSTNAME=raspberrypi', 'SEARXNG_HOSTNAME=$(hostname)'))) {
    Test-Case 'Ambiguous/invalid effective environment input fails before publication' {
        param($fixture)
        Set-FixturePrivateFile -Path (Join-Path $fixture.Source '.env') -Content $content
        $result = Invoke-DeployFixture $fixture
        Assert-DeployFailed $result 'duplicate|invalid literal|invalid SEARXNG_PORT'
        Assert-True ($result.Calls.Count -eq 0 -and -not (Test-Path -LiteralPath $fixture.Target)) 'Invalid input reached publication.'
    }
}

Test-Case 'Missing source env preserves custom deployed config and key byte-for-byte with honest output' {
    param($fixture)
    Initialize-DeployedFixture -Fixture $fixture -Environment ((Get-FixtureEnvironment -Port 9080 -Hostname 'custom.example') + "# retain this comment`n")
    Remove-Item -LiteralPath (Join-Path $fixture.Source '.env')
    $hash = Get-FixtureHash (Join-Path $fixture.Target '.env')
    $result = Invoke-DeployFixture $fixture
    Assert-DeploySucceeded $result
    Assert-True ((Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq $hash) 'Absent source env overwrote retained configuration.'
    Assert-True ($result.Output.Contains('Preserving deployed .env') -and -not $result.Output.Contains('using defaults')) 'Output misreported retained configuration as defaults.'
}

Test-Case 'Missing source and deployed env fails without creating a target' {
    param($fixture)
    Remove-Item -LiteralPath (Join-Path $fixture.Source '.env')
    $result = Invoke-DeployFixture $fixture
    Assert-DeployFailed $result 'No source .env or valid deployed .env'
    Assert-True ($result.Calls.Count -eq 0 -and -not (Test-Path -LiteralPath $fixture.Target)) 'Missing key reached target mutation.'
}

foreach ($location in @('source', 'deployed')) {
    Test-Case "A broadly readable $location env fails preflight without changing its key or ACL" {
        param($fixture)
        $path = Join-Path $fixture.Source '.env'
        if ($location -eq 'deployed') {
            Initialize-DeployedFixture $fixture
            Remove-Item -LiteralPath $path
            $path = Join-Path $fixture.Target '.env'
        }
        $acl = Get-Acl -LiteralPath $path
        $everyone = [System.Security.Principal.SecurityIdentifier]::new('S-1-1-0')
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($everyone, 'Read', 'Allow'))
        Set-Acl -LiteralPath $path -AclObject $acl
        $hash = Get-FixtureHash $path
        $sddl = (Get-Acl -LiteralPath $path).Sddl
        $result = Invoke-DeployFixture $fixture
        Assert-DeployFailed $result 'grants access beyond'
        Assert-True ($result.Calls.Count -eq 0 -and (Get-FixtureHash $path) -eq $hash -and (Get-Acl -LiteralPath $path).Sddl -eq $sddl) 'Privacy preflight mutated inputs or ran Docker.'
    }
}

Test-Case 'Require policy rejects absent source env even when valid deployed env exists' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    Remove-Item -LiteralPath (Join-Path $fixture.Source '.env')
    $hash = Get-FixtureHash (Join-Path $fixture.Target '.env')
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ EnvPolicy = 'Require' }
    Assert-DeployFailed $result 'requires a valid source .env'
    Assert-True ($result.Calls.Count -eq 0 -and (Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq $hash) 'Require policy changed target state.'
}

Test-Case 'Explicit reset restores example hostname/port, ignores source config and retains target key' {
    param($fixture)
    Initialize-DeployedFixture -Fixture $fixture -Environment (Get-FixtureEnvironment -Port 9080 -Hostname 'custom.example')
    Set-FixturePrivateFile -Path (Join-Path $fixture.Source '.env') -Content (Get-FixtureEnvironment -Key $script:AlternateFixtureKey -Port 9999)
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ EnvPolicy = 'Reset' }
    Assert-DeploySucceeded $result
    $text = [System.IO.File]::ReadAllText((Join-Path $fixture.Target '.env'))
    Assert-True ($text -match '(?m)^SEARXNG_HOSTNAME=raspberrypi\r?$' -and $text -match '(?m)^SEARXNG_PORT=8080\r?$') 'Reset did not restore example defaults.'
    Assert-True ($text.Contains($script:FixtureKey) -and -not $text.Contains($script:AlternateFixtureKey)) 'Reset rotated or lost the deployed key.'
    Assert-True ($result.Output.Contains('Explicit reset')) 'Reset was not reported explicitly.'
}

Test-Case 'Reset cannot invent a target key' {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ EnvPolicy = 'Reset' }
    Assert-DeployFailed $result 'No source .env or valid deployed .env'
    Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Reset bootstrapped an unapproved target key.'
}

Test-Case 'Unapproved rotation fails before overwriting target files; explicit rotation persists the new key' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    $hash = Get-FixtureHash (Join-Path $fixture.Target '.env')
    Set-FixturePrivateFile -Path (Join-Path $fixture.Source '.env') -Content (Get-FixtureEnvironment -Key $script:AlternateFixtureKey)
    $result = Invoke-DeployFixture $fixture
    Assert-DeployFailed $result 'keys differ'
    Assert-True ($result.Calls.Count -eq 0 -and (Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq $hash) 'Unapproved rotation mutated deployed inputs.'
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ RotateSecret = $true } -Scenario @{ EffectiveSecret = $script:AlternateFixtureKey }
    Assert-DeploySucceeded $result
    Assert-True ((Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq (Get-FixtureHash (Join-Path $fixture.Source '.env'))) 'Explicit rotation did not persist the new environment.'
    Assert-DeploySucceeded (Invoke-DeployFixture -Fixture $fixture -Scenario @{ EffectiveSecret = $script:AlternateFixtureKey })
}

Test-Case 'Invalid legacy target key requires explicit replacement even with a valid source key' {
    param($fixture)
    Initialize-DeployedFixture -Fixture $fixture -Environment (Get-FixtureEnvironment -Key 'CHANGE_ME_TO_A_RANDOM_SECRET')
    $result = Invoke-DeployFixture $fixture
    Assert-DeployFailed $result 'Deployed .env requires SEARXNG_SECRET'
    Assert-True ($result.Calls.Count -eq 0) 'Invalid deployed key reached Docker.'
    Assert-DeploySucceeded (Invoke-DeployFixture -Fixture $fixture -Parameters @{ RotateSecret = $true })
}

foreach ($parameters in @(@{ SkipCopy = $true; EnvPolicy = 'Reset' }, @{ SkipCopy = $true; EnvPolicy = 'Require' },
        @{ SkipCopy = $true; RotateSecret = $true }, @{ RotateSecret = $true; EnvPolicy = 'Reset' })) {
    Test-Case 'Contradictory copy/environment/rotation switches fail before target actions' {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters $parameters
        Assert-DeployFailed $result 'cannot|preserves'
        Assert-True ($result.Calls.Count -eq 0 -and -not (Test-Path -LiteralPath $fixture.Target)) 'Contradictory switches reached mutation.'
    }
}

Test-Case 'Initializer generates once, protects the file, preserves settings and rotates only explicitly' {
    param($fixture)
    $envPath = Join-Path $fixture.Source '.env'
    Remove-Item -LiteralPath $envPath
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize
    Assert-True ($result.ExitCode -eq 0) "Initializer failed. $($result.Output)"
    $text = [System.IO.File]::ReadAllText($envPath)
    Assert-True ($text -match '(?m)^SEARXNG_SECRET=([a-f0-9]{64})$') 'Initializer did not create the required key shape.'
    $key = $Matches[1]
    Assert-True (-not $result.Output.Contains($key)) 'Initializer printed its generated fixture key.'
    Assert-True ((Get-Acl -LiteralPath $envPath).AreAccessRulesProtected) 'Initializer did not restrict inherited file access.'
    $hash = Get-FixtureHash $envPath
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize
    Assert-True ($result.ExitCode -eq 0 -and (Get-FixtureHash $envPath) -eq $hash) 'Initializer changed an existing valid environment/key.'
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize -Parameters @{ RotateSecret = $true }
    Assert-True ($result.ExitCode -eq 0) 'Explicit initializer rotation failed.'
    $rotated = [System.IO.File]::ReadAllText($envPath)
    Assert-True (-not $rotated.Contains($key) -and $rotated -match '(?m)^SEARXNG_PORT=8080\r?$') 'Rotation did not replace only the key.'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture.Source -Force -Filter '.env.*.tmp').Count -eq 0) 'Private staging files were left behind.'
}

Test-Case 'Initializer rejects an existing invalid key without rotation authorization' {
    param($fixture)
    $envPath = Join-Path $fixture.Source '.env'
    Set-FixturePrivateFile -Path $envPath -Content (Get-FixtureEnvironment -Key 'placeholder')
    $hash = Get-FixtureHash $envPath
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize
    Assert-DeployFailed $result 'Existing SEARXNG_SECRET is invalid'
    Assert-True ((Get-FixtureHash $envPath) -eq $hash) 'Invalid existing environment was silently replaced.'
}

foreach ($mode in @('Local', 'Remote', 'WSL')) {
    Test-Case "WhatIf $mode has zero native calls, zero target/env writes and no ready banner" {
        param($fixture)
        Remove-Item -LiteralPath (Join-Path $fixture.Source '.env')
        $path = if ($mode -eq 'Local') { $fixture.Target } else { '~/DockerScripts' }
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = $mode; RemotePath = $path; WhatIf = $true }
        Assert-True ($result.ExitCode -eq 0) "Preview failed. $($result.Output)"
        Assert-True ($result.Calls.Count -eq 0) 'Preview invoked a native command.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target) -and -not (Test-Path -LiteralPath (Join-Path $fixture.Source '.env'))) 'Preview wrote files or generated a key.'
        Assert-True ($result.Output.Contains('unverified') -and -not $result.Output.Contains('MCP stack is ready')) 'Preview claimed readiness or hid unverified state.'
    }
}

Test-Case 'Initializer WhatIf neither generates nor rotates keys/files' {
    param($fixture)
    $path = Join-Path $fixture.Source '.env'
    $hash = Get-FixtureHash $path
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize -Parameters @{ RotateSecret = $true; WhatIf = $true }
    Assert-True ($result.ExitCode -eq 0 -and (Get-FixtureHash $path) -eq $hash -and $result.Calls.Count -eq 0) 'Initializer preview changed an existing key.'
    Remove-Item -LiteralPath $path
    $result = Invoke-DeployFixture -Fixture $fixture -Operation initialize -Parameters @{ WhatIf = $true }
    Assert-True ($result.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $path) -and $result.Calls.Count -eq 0) 'Initializer preview generated a file/key.'
}

Test-Case 'Deployment WhatIf leaves existing source/target bytes and keys unchanged during planned rotation' {
    param($fixture)
    Initialize-DeployedFixture $fixture
    Set-FixturePrivateFile -Path (Join-Path $fixture.Source '.env') -Content (Get-FixtureEnvironment -Key $script:AlternateFixtureKey)
    $sourceHash = Get-FixtureHash (Join-Path $fixture.Source '.env')
    $targetHash = Get-FixtureHash (Join-Path $fixture.Target '.env')
    $settingsHash = Get-FixtureHash (Join-Path $fixture.Target 'searxng\settings.yml')
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ WhatIf = $true; RotateSecret = $true }
    Assert-True ($result.ExitCode -eq 0 -and $result.Calls.Count -eq 0) 'Planned rotation invoked native commands during preview.'
    Assert-True ((Get-FixtureHash (Join-Path $fixture.Source '.env')) -eq $sourceHash -and
        (Get-FixtureHash (Join-Path $fixture.Target '.env')) -eq $targetHash -and
        (Get-FixtureHash (Join-Path $fixture.Target 'searxng\settings.yml')) -eq $settingsHash) 'Preview changed existing files.'
    Assert-True (-not $result.Output.Contains('MCP stack is ready') -and $result.Output.Contains('unverified')) 'Preview overstated its evidence.'
}

foreach ($preview in @($true, $false)) {
    Test-Case "Direct pwsh -File entry point returns an honest process status (preview=$preview)" {
        param($fixture)
        $arguments = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $fixture.Source 'deploy.ps1'),
            '-DeployMode', 'Local', '-RemotePath', $fixture.Target)
        if ($preview) { $arguments += '-WhatIf' }
        else { Remove-Item -LiteralPath (Join-Path $fixture.Source 'docker-compose.yml') }
        $result = Invoke-FixtureProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList $arguments -WorkingDirectory $fixture.Root `
            -Environment @{ PATH = $fixture.Root; COPILOT_HOME = (Join-Path $fixture.Root 'unused-home') }
        $expected = if ($preview) { 0 } else { 1 }
        Assert-True ($result.ExitCode -eq $expected) 'Direct entry process status disagrees with the requested preview/preflight outcome.'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Direct preview/preflight created a target.'
    }
}

Test-Case 'Readiness can transition from starting to healthy within the deadline' {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ Statuses = @('starting', 'healthy') }
    Assert-DeploySucceeded $result
    $polls = @($result.Calls | Where-Object Description -eq 'Read SearXNG readiness')
    Assert-True ($polls.Count -eq 2 -and $polls[1].TimeoutMilliseconds -lt $polls[0].TimeoutMilliseconds) 'Polling did not share a bounded deadline.'
}

Test-Case 'Readiness supports Compose newline-delimited JSON as well as arrays' {
    param($fixture)
    Assert-DeploySucceeded (Invoke-DeployFixture -Fixture $fixture -Scenario @{ Statuses = @('ndjson') })
}

foreach ($state in @('unhealthy', 'exited', 'missing', 'empty', 'no-health', 'no-healthcheck', 'malformed', 'duplicate')) {
    Test-Case "Readiness rejects $state without success" {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Scenario @{ Statuses = @($state) }
        Assert-DeployFailed $result 'unhealthy|missing|health|JSON|ambiguous'
    }
}

Test-Case 'Readiness starting forever fails at the configured one-second deadline' {
    param($fixture)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ ReadinessTimeoutSeconds = 1 } -Scenario @{ Statuses = @('starting') }
    Assert-DeployFailed $result 'readiness timed out after 1 seconds'
    Assert-True ($clock.Elapsed.TotalSeconds -ge 1 -and $clock.Elapsed.TotalSeconds -lt 10) 'Readiness timeout was unbounded or did not wait for its configured interval.'
    foreach ($poll in @($result.Calls | Where-Object Description -eq 'Read SearXNG readiness')) {
        Assert-True ($poll.TimeoutMilliseconds -gt 0 -and $poll.TimeoutMilliseconds -le 1000) 'Status command exceeded the health deadline.'
    }
}

foreach ($scenario in @(@{ MissingSecretMapping = $true }, @{ ForwardHostPort = $true }, @{ GlobalContainerName = $true },
        @{ GlobalNetworkName = $true }, @{ InvalidComposeJson = $true }, @{ EffectiveSecret = $script:AlternateFixtureKey })) {
    Test-Case 'SkipCopy validates effective deployed Compose mapping/isolation before pull/up' {
        param($fixture)
        Initialize-DeployedFixture $fixture
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ SkipCopy = $true } -Scenario $scenario
        Assert-DeployFailed $result 'Compose|SEARXNG|isolat|JSON'
        Assert-True ($result.Calls.Count -eq 1 -and $result.Calls[0].Description -eq 'Validate deployed Compose configuration') 'Invalid deployed Compose reached pull/up.'
    }
}

Test-Case 'Remote SSH argv, home-relative input, private stdin and project isolation survive shell parsing' -Skip:(-not $hasGitBash) {
    param($fixture)
    $path = "~/DockerScripts/O'Brien [x];`$literal"
    $compose = "team's search [1];`$file.yml"
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = 'Remote'; RemotePath = $path; ComposeFile = $compose }
    Assert-DeploySucceeded $result
    $resolve = $result.Calls[0]
    Assert-Arguments $resolve.ArgumentList[0..5] @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '--', 'pi@raspberrypi') 'SSH target/options boundary changed.'
    $resolveTokens = @(Get-PosixTokens -Command $resolve.ArgumentList[-1] -Fixture $fixture)
    Assert-Arguments $resolveTokens[0..1] @('sh', '-c') 'Remote command did not use an explicit shell.'
    Assert-True ($resolveTokens[4] -ceq $path) 'Home-relative path changed before target-side resolution.'
    $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
    $tokens = @(Get-PosixTokens -Command $up.ArgumentList[-1] -Fixture $fixture)
    $resolved = "/home/test O'Brien/DockerScripts/stack [1];`$literal"
    Assert-Arguments $tokens[4..($tokens.Count - 1)] @($resolved, 'compose', '--project-name', 'np-copilot-mcp',
        '--project-directory', $resolved, '--env-file', "$resolved/.env", '-f', "$resolved/$compose",
        'up', '-d', '--no-deps', '--force-recreate', 'searxng') 'SSH shell changed Compose argv.'
    $copy = @($result.Calls | Where-Object Description -eq 'Publish private .env')[0]
    Assert-True ($copy.InputHash -eq (Get-FixtureHash (Join-Path $fixture.Source '.env'))) 'Remote private file was not transferred through stdin intact.'
    Assert-True (-not ([System.IO.File]::ReadAllText($fixture.Log)).Contains($script:FixtureKey)) 'Secret was included in native arguments or logs.'
    Assert-True (-not ([System.IO.File]::ReadAllText($fixture.Log)).Contains('--remove-orphans')) 'Deployment enabled cross-stack orphan removal.'
}

foreach ($distro in @('', "Ubuntu O'Brien 24.04")) {
    Test-Case "WSL keeps distro and source paths literal, with no host wslpath evaluation ($distro)" {
        param($fixture)
        $compose = "team's compose [x].yml"
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{
            DeployMode = 'WSL'; RemotePath = "~/DockerScripts/O'Brien stack"; WslDistro = $distro; ComposeFile = $compose
        }
        Assert-DeploySucceeded $result
        $copy = @($result.Calls | Where-Object Description -eq 'Publish SearXNG settings')[0]
        $offset = if ($distro) { 2 } else { 0 }
        if ($distro) { Assert-Arguments $copy.ArgumentList[0..1] @('--distribution', $distro) 'WSL distribution was split.' }
        Assert-Arguments $copy.ArgumentList[$offset..($offset + 2)] @('--exec', 'sh', '-c') 'WSL introduced an extra host shell.'
        Assert-True ($copy.ArgumentList[$offset + 3].Contains('source=$(wslpath -u "$1")')) 'WSL copy lost target-side conversion.'
        Assert-True ($copy.ArgumentList[$offset + 5] -ceq (Join-Path $fixture.Source 'searxng\settings.yml')) 'Windows source path was interpolated or split.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.Root 'host-wslpath-called'))) 'wslpath executed on the Windows host.'
        $up = @($result.Calls | Where-Object Description -eq 'Start SearXNG')[0]
        Assert-True ($up.ArgumentList -contains ("/home/test O'Brien/DockerScripts/stack [1];`$literal/" + $compose)) 'Custom Compose filename was not passed intact into WSL.'
    }
}

Test-Case 'WSL copy script executes conversion inside a local controlled shell and copies actual fixture bytes' -Skip:(-not $hasGitBash) {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = 'WSL'; RemotePath = '~/DockerScripts' }
    Assert-DeploySucceeded $result
    $copy = @($result.Calls | Where-Object Description -eq 'Publish SearXNG settings')[0]
    $source = Join-Path $fixture.Source 'searxng\settings.yml'
    $destination = Join-Path $fixture.Root "shell copy O'Brien [x].yml"
    $conversionLog = Join-Path $fixture.Root 'wslpath-arguments.bin'
    $prefix = 'wslpath() { printf ''%s\0'' "$@" > "$NP_WSLPATH_LOG"; printf ''%s'' "$NP_SOURCE_POSIX"; }; '
    $shell = Invoke-FixtureProcess -FilePath $script:GitBash -ArgumentList @('--noprofile', '--norc', '-c',
        ($prefix + $copy.ArgumentList[3]), 'np-mcp', $source, $destination.Replace('\', '/'), 'public') -WorkingDirectory $fixture.Root `
        -Environment @{ NP_WSLPATH_LOG = $conversionLog.Replace('\', '/'); NP_SOURCE_POSIX = $source.Replace('\', '/') } `
        -RemoveEnvironment @('BASH_ENV', 'ENV', 'SHELLOPTS', 'BASHOPTS')
    Assert-True ($shell.ExitCode -eq 0) "Local WSL-script probe failed. $($shell.Error)"
    Assert-True ((Get-FixtureHash $source) -eq (Get-FixtureHash $destination)) 'WSL-script probe copied wrong bytes.'
    $arguments = [System.IO.File]::ReadAllText($conversionLog).TrimEnd([char]0).Split([char]0)
    Assert-Arguments $arguments @('-u', $source) 'wslpath did not receive the literal Windows source argument.'
}

Test-Case 'Target-side tilde resolution uses HOME as data and preserves apostrophes/spaces' -Skip:(-not $hasGitBash) {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = 'WSL'; RemotePath = "~/O'Brien stack" }
    $resolve = $result.Calls[0].ArgumentList[3]
    $shell = Invoke-FixtureProcess -FilePath $script:GitBash -ArgumentList @('--noprofile', '--norc', '-c', $resolve, 'np-mcp', "~/O'Brien stack") `
        -WorkingDirectory $fixture.Root -Environment @{ HOME = "/home/user's folder" } -RemoveEnvironment @('BASH_ENV', 'ENV')
    Assert-True ($shell.ExitCode -eq 0 -and $shell.Output -ceq "/home/user's folder/O'Brien stack") 'Quoted tilde was not resolved against target HOME.'
}

Test-Case 'Failed WSL source conversion stops before copying in the controlled local shell' -Skip:(-not $hasGitBash) {
    param($fixture)
    $result = Invoke-DeployFixture -Fixture $fixture -Parameters @{ DeployMode = 'WSL'; RemotePath = '~/DockerScripts' }
    Assert-DeploySucceeded $result
    $copy = @($result.Calls | Where-Object Description -eq 'Publish SearXNG settings')[0]
    $destination = Join-Path $fixture.Root 'must-not-be-overwritten.yml'
    [System.IO.File]::WriteAllText($destination, 'existing fixture content')
    $hash = Get-FixtureHash $destination
    $shell = Invoke-FixtureProcess -FilePath $script:GitBash -ArgumentList @('--noprofile', '--norc', '-c',
        ('wslpath() { return 31; }; ' + $copy.ArgumentList[3]), 'np-mcp', (Join-Path $fixture.Source 'searxng\settings.yml'),
        $destination.Replace('\', '/'), 'public') -WorkingDirectory $fixture.Root -RemoveEnvironment @('BASH_ENV', 'ENV')
    Assert-True ($shell.ExitCode -eq 31 -and (Get-FixtureHash $destination) -eq $hash) 'WSL conversion failure was hidden or allowed a copy.'
}

Test-Case 'Local tilde resolution is explicit and read-only' {
    param($fixture)
    $resolved = Invoke-FixtureModule -Fixture $fixture -Script {
        Resolve-DeploymentPath -Context ([pscustomobject]@{ Mode = 'Local' }) -Path "~\O'Brien [x]"
    }
    Assert-True ($resolved -ceq (Join-Path $HOME "O'Brien [x]")) 'Local home-relative destination was not resolved literally.'
    Assert-True (-not (Test-Path -LiteralPath $fixture.Target)) 'Resolving a path created a target.'
}

foreach ($parameters in @(@{ DeployMode = 'Remote'; RemotePath = '~someone/stack' },
        @{ ComposeFile = '..\wrong.yml' }, @{ ProjectName = '--foreign' },
        @{ DeployMode = 'Remote'; RemotePath = '~/stack'; TargetHost = '-oProxyCommand=anything' })) {
    Test-Case 'Invalid target/identity inputs are rejected before all native actions' {
        param($fixture)
        $result = Invoke-DeployFixture -Fixture $fixture -Parameters $parameters
        Assert-DeployFailed $result 'path|filename|pattern|SSH|parameter'
        Assert-True ($result.Calls.Count -eq 0) 'Invalid target/identity reached a native process.'
    }
}

Test-Case 'Real native helper preserves argv/stdin and removes inherited input overrides without shell evaluation' {
    param($fixture)
    $arguments = @("a'b", 'two words', 'a"b', '[brackets];$literal', 'C:\folder with spaces\trailing\', '')
    $probe = Join-Path $PSScriptRoot 'Native-Probe.ps1'
    $inputText = "fixture stdin with ' and `" and `$`n"
    $output = Invoke-FixtureModule -Fixture $fixture -Script {
        param($Pwsh, $Probe, $Arguments, $Root, $InputText)
        $oldPort = $env:SEARXNG_PORT
        try {
            $env:SEARXNG_PORT = '9933'
            $control = Invoke-DeployNative -FilePath $Pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $Probe, 'echo') `
                -WorkingDirectory $Root -Description 'Isolated native environment control'
            if ((ConvertFrom-Json -InputObject $control).Port -ne '9933') { throw 'Native environment control did not reach the child.' }
            Invoke-DeployNative -FilePath $Pwsh -ArgumentList (@('-NoProfile', '-NonInteractive', '-File', $Probe, 'echo') + $Arguments) `
                -WorkingDirectory $Root -InputBytes ([System.Text.Encoding]::UTF8.GetBytes($InputText)) -RemoveEnvironment @('SEARXNG_PORT') `
                -TimeoutMilliseconds 10000 -Description 'Isolated native argv probe'
        }
        finally { $env:SEARXNG_PORT = $oldPort }
    } -ArgumentList @((Join-Path $PSHOME 'pwsh.exe'), $probe, $arguments, $fixture.Root, $inputText)
    $model = ConvertFrom-Json -InputObject $output
    Assert-Arguments $model.Arguments $arguments 'Native ProcessStartInfo changed argument boundaries.'
    Assert-True ($model.Input -ceq $inputText) 'Native stdin bytes changed.'
    Assert-True ([string]::IsNullOrEmpty($model.Port)) 'Removed environment variable reached the child.'
}

Test-Case 'Real native process exit is checked immediately and private stdout/stderr are not in the exception' {
    param($fixture)
    $caught = $null
    try {
        Invoke-FixtureModule -Fixture $fixture -Script {
            param($Pwsh, $Probe, $Root)
            Invoke-DeployNative -FilePath $Pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $Probe, 'fail') `
                -WorkingDirectory $Root -TimeoutMilliseconds 10000 -Description 'Isolated native failure probe'
        } -ArgumentList @((Join-Path $PSHOME 'pwsh.exe'), (Join-Path $PSScriptRoot 'Native-Probe.ps1'), $fixture.Root)
    }
    catch { $caught = $_ }
    Assert-True ($null -ne $caught -and $caught.Exception.Data['ExitCode'] -eq 47) 'Real native failure was not propagated.'
    Assert-True ($caught.Exception.Message -notmatch 'private-looking') 'Raw native stdout/stderr leaked through the exception.'
}

Test-Case 'Real stalled native process is bounded and its owned process is reaped' {
    param($fixture)
    $pidPath = Join-Path $fixture.Root 'probe.pid'
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $caught = $null
    try {
        Invoke-FixtureModule -Fixture $fixture -Script {
            param($Pwsh, $Probe, $Root, $PidPath)
            Invoke-DeployNative -FilePath $Pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $Probe, 'sleep', $PidPath) `
                -WorkingDirectory $Root -TimeoutMilliseconds 1500 -Description 'Isolated native timeout probe'
        } -ArgumentList @((Join-Path $PSHOME 'pwsh.exe'), (Join-Path $PSScriptRoot 'Native-Probe.ps1'), $fixture.Root, $pidPath)
    }
    catch { $caught = $_ }
    Assert-True ($null -ne $caught -and $caught.Exception.Data['ExitCode'] -eq 124 -and $clock.Elapsed.TotalSeconds -lt 8) 'Real native process timeout was not bounded.'
    Assert-True (Test-Path -LiteralPath $pidPath) 'Native timeout probe never started; missing execution evidence.'
    $probeId = [int][System.IO.File]::ReadAllText($pidPath)
    $remaining = Get-Process -Id $probeId -ErrorAction SilentlyContinue
    if ($remaining) {
        Stop-Process -Id $probeId -Force
        throw 'Native timeout left its owned probe process running.'
    }
}

Test-Case 'Native timeout bounds inherited stdout/stderr after the parent already exited' {
    param($fixture)
    Test-InheritedOutputTimeout -Fixture $fixture | Out-Null
}

Test-Case 'Inherited-output timeout propagates as redacted native exit 124' {
    param($fixture)
    Test-InheritedOutputTimeout -Fixture $fixture -ThroughNativeWrapper | Out-Null
}

Test-Case 'Read-only Compose parsing enforces key mapping, internal 8080, pins and project-scoped names' -Skip:($null -eq $docker) {
    param($fixture)
    $emptyEnv = Join-Path $fixture.Root 'empty.env'
    [System.IO.File]::WriteAllText($emptyEnv, '')
    Copy-Item -LiteralPath (Join-Path $fixture.Source 'docker-compose.yml') -Destination (Join-Path $fixture.Root 'compose-fixture.yml')
    Set-FixturePrivateFile -Path (Join-Path $fixture.Root 'compose-fixture.env') -Content (Get-FixtureEnvironment -Port 9080 -Hostname 'example.test')
    $args = @('compose', '--project-name', 'np-copilot-mcp', '--env-file', 'compose-fixture.env', '-f', 'compose-fixture.yml', 'config', '--format', 'json')
    $remove = @('SEARXNG_SECRET', 'SEARXNG_PORT', 'SEARXNG_HOSTNAME', 'COMPOSE_FILE', 'COMPOSE_PROJECT_NAME', 'COMPOSE_ENV_FILES', 'COMPOSE_PROFILES')
    $result = Invoke-FixtureProcess -FilePath $docker.Source -ArgumentList $args -WorkingDirectory $fixture.Root -RemoveEnvironment $remove
    Assert-True ($result.ExitCode -eq 0) 'Read-only Compose config parsing failed; output withheld.'
    $model = ConvertFrom-Json -InputObject $result.Output -AsHashtable
    Assert-True ($model.services.Count -eq 1 -and $model.services.Contains('searxng')) 'Compose unexpectedly defines a remote browser/extra service.'
    $service = $model.services.searxng
    Assert-True ($service.image -ceq 'searxng/searxng:2026.8.22-9fea41204') 'SearXNG pin changed.'
    Assert-True ($service.environment.SEARXNG_SECRET -ceq $script:FixtureKey -and -not $service.environment.Contains('SEARXNG_PORT')) 'Compose forwards incorrect environment inputs.'
    Assert-True ($service.environment.SEARXNG_BASE_URL -ceq 'http://example.test:9080/') 'Advertised URL did not follow host settings.'
    Assert-True ($service.ports[0].target -eq 8080 -and $service.ports[0].published -eq '9080') 'Custom host port changed the internal listener port.'
    Assert-True ($service.healthcheck.test -contains 'http://localhost:8080/healthz') 'Healthcheck moved off internal 8080.'
    Assert-True (-not $service.Contains('container_name') -and $model.networks.'mcp-network'.name -ceq 'np-copilot-mcp_mcp-network') 'Compose still uses global container/network names.'
    Assert-True ($service.volumes[0].read_only) 'Settings mount is no longer read-only.'
    $args[4] = 'empty.env'
    $result = Invoke-FixtureProcess -FilePath $docker.Source -ArgumentList $args -WorkingDirectory $fixture.Root -RemoveEnvironment $remove
    Assert-True ($result.ExitCode -ne 0) 'Compose accepted a missing key when no private environment was provided.'
}

foreach ($path in $guardPaths) {
    if ((Get-FixtureHash $path) -ne $before[$path]) {
        $script:TestsFailed++
        Write-Host "  FAIL repository preservation: $path" -ForegroundColor Red
    }
}
if ($script:DeployFixtureRoots.Count -ne 0) {
    $script:TestsFailed++
    Write-Host '  FAIL owned fixtures remain after cleanup.' -ForegroundColor Red
}
Write-Host "`nDeploy tests: $script:TestsPassed passed, $script:TestsFailed failed, $script:TestsSkipped skipped."
if ($script:TestsFailed) { exit 1 }
exit 0
