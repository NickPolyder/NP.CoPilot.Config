#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function New-ConfigHookFixture {
    $root = New-IsolatedGitRepo
    $baseline = New-BaselineFixture
    foreach ($item in Get-ChildItem -LiteralPath $baseline -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $root -Recurse
    }
    Remove-FixtureRoot -Path $baseline
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'scripts')
    foreach ($name in @('Validate-Config.ps1', 'ConfigurationParsing.psm1', 'IsolatedProcess.psm1',
        'GitSnapshot.psm1', 'Invoke-ConfigPreCommitHook.ps1', 'Enable-ConfigGitHook.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\$name") -Destination (Join-Path $root 'scripts')
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $root '.githooks')
    Copy-Item -LiteralPath (Join-Path $repoRoot '.githooks\pre-commit') -Destination (Join-Path $root '.githooks')
    $null = Invoke-Git $root @('add', '.')
    $null = Invoke-Git $root @('commit', '-q', '-m', 'hook fixture baseline')
    $root
}

function Invoke-ConfigHookFixture {
    param([string]$Root, [hashtable]$Environment = @{})
    Invoke-IsolatedProcess -Context $script:GitFixtureContexts[$Root] -FilePath (Get-Command pwsh).Source `
        -WorkingDirectory $Root -ArgumentList @('-NoProfile', '-File', (Join-Path $Root 'scripts\Invoke-ConfigPreCommitHook.ps1')) `
        -Environment $Environment -AllowFailure
}
