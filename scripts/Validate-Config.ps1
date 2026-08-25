#Requires -Version 7.0
<#
.SYNOPSIS
    Validates structural invariants for the Copilot configuration repository.

.DESCRIPTION
    Checks tracked configuration files without modifying them. The validator
    intentionally reports legacy metadata and documentation drift until the
    corresponding hardening phases remove them.
#>

[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),

    [switch]$SkipDockerCompose
)

$ErrorActionPreference = 'Stop'

$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Passes = 0

$supportedModels = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'claude-opus-4.8',
        'claude-sonnet-5',
        'gpt-5.5'
    ),
    [System.StringComparer]::Ordinal
)

$reviewInvariants = @(
    @{
        Path = 'skills/git-commit-review/SKILL.md'
        Name = 'Git commit review materializes an index-only snapshot'
        Pattern = '(?s)git write-tree.*git archive --format=tar'
    }
    @{
        Path = 'skills/git-commit-review/SKILL.md'
        Name = 'Git commit review blocks reviewers after snapshot failure'
        Pattern = '(?is)snapshot cannot be materialized.*stop.*before launching any reviewer'
    }
    @{
        Path = 'skills/full-code-review/SKILL.md'
        Name = 'Full review requires explicit user invocation'
        Pattern = '(?is)only when the user explicitly requests'
    }
)

$orchestration = @{
    'prd-workflow' = @(
        'codebase-research',
        'feature-design-doc',
        'task-breakdown',
        'implementation-runner'
    )
    'dependency-audit' = @(
        'dependency-audit-report',
        'dependency-upgrade-execution'
    )
    'test-gap-analysis' = @(
        'test-gap-audit',
        'test-gap-fill'
    )
}

$reviewerExpectedTools = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'read',
        'search'
    ),
    [System.StringComparer]::Ordinal
)

function Write-Pass {
    param([Parameter(Mandatory)][string]$Message)

    $script:Passes++
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)

    $script:Failures.Add($Message)
    Write-Host "  ❌ $Message" -ForegroundColor Red
}

function Add-Warning {
    param([Parameter(Mandatory)][string]$Message)

    $script:Warnings.Add($Message)
    Write-Host "  ⚠️ $Message" -ForegroundColor Yellow
}

function Get-Frontmatter {
    param([Parameter(Mandatory)][string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $match = [regex]::Match($content, '\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n', 'Singleline')

    if (-not $match.Success) {
        Add-Failure "$Path does not start with a closed YAML frontmatter block."
        return $null
    }

    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $match.Groups['frontmatter'].Value -split '\r?\n') {
        if ($line -match '^(?<key>[A-Za-z][A-Za-z0-9-]*):') {
            $keys.Add($matches['key'])
        }
    }

    [pscustomobject]@{
        Content = $content
        Keys = $keys
        Text = $match.Groups['frontmatter'].Value
    }
}

function Get-FrontmatterList {
    param(
        [Parameter(Mandatory)][string]$Frontmatter,
        [Parameter(Mandatory)][string]$Key
    )

    $escapedKey = [regex]::Escape($Key)
    $inlineMatch = [regex]::Match(
        $Frontmatter,
        "(?m)^$escapedKey\s*:\s*\[(?<items>[^\]]*)\]\s*$"
    )
    if ($inlineMatch.Success) {
        $values = @(
            $inlineMatch.Groups['items'].Value -split ',' |
                ForEach-Object { $_.Trim().Trim('"', "'") } |
                Where-Object { $_ }
        )
        return [pscustomobject]@{
            Present = $true
            Values = [string[]]$values
        }
    }

    $blockMatch = [regex]::Match(
        $Frontmatter,
        "(?ms)^$escapedKey\s*:\s*\r?\n(?<items>(?:[ \t]+-\s*[^\r\n]+\r?\n?)*)"
    )
    if ($blockMatch.Success) {
        $values = @(
            [regex]::Matches($blockMatch.Groups['items'].Value, '(?m)^[ \t]+-\s*(?<item>[^\r\n]+)\s*$') |
                ForEach-Object { $_.Groups['item'].Value.Trim().Trim('"', "'") }
        )
        return [pscustomobject]@{
            Present = $true
            Values = [string[]]$values
        }
    }

    [pscustomobject]@{
        Present = $false
        Values = [string[]]@()
    }
}

function Test-DefinitionFrontmatter {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedName,
        [Parameter(Mandatory)][string[]]$AllowedKeys
    )

    $failureCount = $script:Failures.Count
    $frontmatter = Get-Frontmatter -Path $Path
    if ($null -eq $frontmatter) {
        return
    }

    foreach ($key in $frontmatter.Keys | Select-Object -Unique) {
        $keyCount = @($frontmatter.Keys | Where-Object { $_ -eq $key }).Count
        if ($keyCount -gt 1) {
            Add-Failure "$Path defines the '$key' frontmatter key $keyCount times."
        }
        if ($key -notin $AllowedKeys) {
            Add-Failure "$Path uses unsupported $Kind frontmatter key '$key'."
        }
    }

    $nameMatch = [regex]::Match($frontmatter.Text, '(?m)^name:\s*(?<name>[^\r\n]+)\s*$')
    if (-not $nameMatch.Success) {
        Add-Failure "$Path has no name frontmatter value."
        return
    }

    $actualName = $nameMatch.Groups['name'].Value.Trim().Trim('"', "'")
    if ($actualName -ne $ExpectedName) {
        Add-Failure "$Path declares name '$actualName' but its expected name is '$ExpectedName'."
    }

    if ($Kind -eq 'agent') {
        $modelMatch = [regex]::Match($frontmatter.Text, '(?m)^model:\s*(?<model>[^\r\n]+)\s*$')
        if (-not $modelMatch.Success) {
            Add-Failure "$Path has no model frontmatter value."
            return
        }

        $model = $modelMatch.Groups['model'].Value.Trim().Trim('"', "'")
        if (-not $supportedModels.Contains($model)) {
            Add-Failure "$Path uses unsupported model '$model'."
        }
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass "$Path has valid $Kind identity metadata."
    }
}

function Get-RoutedReferences {
    param([Parameter(Mandatory)][string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $routingPattern = '(?im)\b(?:agent|skill|delegate(?:s)?(?:\s+\w+)?\s+to|consult|route(?:s)?(?:\s+to)?|handoff(?:s)?(?:\s+to)?)\s*(?:the\s+)?`(?<reference>[a-z][a-z0-9-]+)`'

    [regex]::Matches($content, $routingPattern) |
        ForEach-Object { $_.Groups['reference'].Value } |
        Sort-Object -Unique
}

function Test-ReferenceIntegrity {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DefinitionPaths,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$KnownAgents,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$KnownSkills
    )

    $failureCount = $script:Failures.Count
    $knownDefinitions = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($KnownAgents + $KnownSkills),
        [System.StringComparer]::Ordinal
    )

    foreach ($path in $DefinitionPaths) {
        foreach ($reference in Get-RoutedReferences -Path $path) {
            if (-not $knownDefinitions.Contains($reference)) {
                Add-Failure "$path references unknown agent or skill '$reference'."
            }
        }
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'Agent and skill backticked references resolve.'
    }
}

function Test-Orchestration {
    param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$KnownSkills)

    $failureCount = $script:Failures.Count
    foreach ($entry in $orchestration.GetEnumerator()) {
        if (-not $KnownSkills.Contains($entry.Key)) {
            Add-Failure "Orchestration entry skill '$($entry.Key)' does not exist."
        }

        foreach ($child in $entry.Value) {
            if (-not $KnownSkills.Contains($child)) {
                Add-Failure "Orchestration child skill '$child' does not exist."
            }
            if ($orchestration.ContainsKey($child)) {
                Add-Failure "Orchestration entry '$($entry.Key)' directly invokes coordinator '$child'."
            }
        }
    }

    $visiting = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    function Test-NodeCycle {
        param([Parameter(Mandatory)][string]$Node)

        if ($visiting.Contains($Node)) {
            Add-Failure "Orchestration graph contains a cycle at '$Node'."
            return
        }
        if ($visited.Contains($Node)) {
            return
        }

        $visiting.Add($Node) | Out-Null
        foreach ($child in @($orchestration[$Node])) {
            if ($orchestration.ContainsKey($child)) {
                Test-NodeCycle -Node $child
            }
        }
        $visiting.Remove($Node) | Out-Null
        $visited.Add($Node) | Out-Null
    }

    foreach ($node in $orchestration.Keys) {
        Test-NodeCycle -Node $node
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'Declared skill orchestration graph is valid.'
    }
}

function Test-ReadmeInventory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AgentNames,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SkillNames
    )

    $failureCount = $script:Failures.Count
    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    foreach ($agent in $AgentNames) {
        if ($content -notmatch [regex]::Escape("$agent.md")) {
            Add-Failure "$Path does not inventory agent '$agent'."
        }
    }
    foreach ($skill in $SkillNames) {
        if ($content -notmatch [regex]::Escape("$skill/")) {
            Add-Failure "$Path does not inventory skill '$skill'."
        }
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'README inventory includes every tracked agent and skill.'
    }
}

function Test-MutableRuntimeVersions {
    param([Parameter(Mandatory)][string[]]$Paths)

    $failureCount = $script:Failures.Count
    foreach ($path in $Paths) {
        $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
        $mutableVersions = @([regex]::Matches($content, '(?i)(@latest|:latest)(?!\w)') | ForEach-Object Value)
        $approvedPlaywrightLatest = @(
            [regex]::Matches($content, '(?i)@playwright/mcp@latest(?!\w)') |
                ForEach-Object Value
        )

        if ($mutableVersions.Count -gt $approvedPlaywrightLatest.Count) {
            Add-Failure "$path contains a mutable runtime version."
        }
        elseif ($approvedPlaywrightLatest.Count -gt 0) {
            Add-Warning "$path intentionally uses @playwright/mcp@latest under the documented user-approved waiver."
        }
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'Runtime MCP definitions use explicit versions or documented waivers.'
    }
}

function Test-Json {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($content)) {
            Add-Failure "$Path is empty and does not contain JSON."
            return
        }

        $content | ConvertFrom-Json -ErrorAction Stop | Out-Null
        Write-Pass "$Path contains valid JSON."
    }
    catch {
        Add-Failure "$Path is not valid JSON: $($_.Exception.Message)"
    }
}

function Test-DockerCompose {
    param([Parameter(Mandatory)][string]$Path)

    if ($SkipDockerCompose) {
        Add-Warning 'Skipped Docker Compose validation by request.'
        return
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Add-Warning 'Docker is unavailable; skipped Docker Compose validation.'
        return
    }

    Push-Location (Split-Path $Path -Parent)
    try {
        & docker compose -f (Split-Path $Path -Leaf) config --quiet
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "$Path failed docker compose config validation."
            return
        }
        Write-Pass "$Path passes docker compose config validation."
    }
    finally {
        Pop-Location
    }
}

function Test-ReviewInvariants {
    foreach ($invariant in $reviewInvariants) {
        $path = Join-Path $RepositoryRoot $invariant.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "$($invariant.Path) is missing; cannot verify review invariant: $($invariant.Name)."
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
        if ($content -notmatch $invariant.Pattern) {
            Add-Failure "$($invariant.Path) violates review invariant: $($invariant.Name)."
            continue
        }
        Write-Pass $invariant.Name
    }
}

function Test-ReviewerCapabilityBoundary {
    $failureCount = $script:Failures.Count
    $reviewerPath = Join-Path $RepositoryRoot 'agents/code-reviewer.md'
    if (-not (Test-Path -LiteralPath $reviewerPath -PathType Leaf)) {
        Add-Failure 'agents/code-reviewer.md is missing; cannot verify reviewer capability boundary.'
        return
    }

    $frontmatter = Get-Frontmatter -Path $reviewerPath
    if ($null -eq $frontmatter) {
        return
    }

    $tools = Get-FrontmatterList -Frontmatter $frontmatter.Text -Key 'tools'
    if (-not $tools.Present) {
        Add-Failure 'agents/code-reviewer.md is missing its reviewer tools list.'
    }
    else {
        $actualTools = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$tools.Values,
            [System.StringComparer]::Ordinal
        )
        foreach ($tool in $actualTools) {
            if (-not $reviewerExpectedTools.Contains($tool)) {
                Add-Failure "agents/code-reviewer.md declares unauthorized reviewer tool '$tool'."
            }
        }
        foreach ($tool in $reviewerExpectedTools) {
            if (-not $actualTools.Contains($tool)) {
                Add-Failure "agents/code-reviewer.md is missing required reviewer tool '$tool'."
            }
        }
        if ($tools.Values.Count -ne $reviewerExpectedTools.Count) {
            Add-Failure 'agents/code-reviewer.md must declare each required reviewer tool exactly once.'
        }
    }

    if (-not $frontmatter.Content.Contains('Do not create reports, directories, or any other artifacts.')) {
        Add-Failure 'agents/code-reviewer.md must explicitly prohibit reviewer-created artifacts.'
    }
    if ($frontmatter.Content -match '(?is)After completing every review.*?\b(?:persist|write|create)\b.*?\breport') {
        Add-Failure 'agents/code-reviewer.md must not claim review-report persistence.'
    }

    foreach ($skillPath in @(
        'skills/git-commit-review/SKILL.md',
        'skills/full-code-review/SKILL.md'
    )) {
        $path = Join-Path $RepositoryRoot $skillPath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "$skillPath is missing; cannot verify workflow-owned report persistence."
            continue
        }
        $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
        if ($content -notmatch '(?is)this workflow owns[^.]*(consolidation|persistence)') {
            Add-Failure "$skillPath must explicitly claim workflow-owned report persistence."
        }
    }

    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'Code reviewer is restricted to read/search and workflows own report persistence.'
    }
}

Write-Host ''
Write-Host '🔍 Validating Copilot configuration...' -ForegroundColor Cyan

$agentPaths = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'agents') -File -Filter '*.md')
$skillPaths = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'skills') -Directory |
    ForEach-Object { Join-Path $_.FullName 'SKILL.md' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })

$knownAgents = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($agentPaths | ForEach-Object BaseName),
    [System.StringComparer]::Ordinal
)
$knownSkills = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($skillPaths | ForEach-Object { Split-Path (Split-Path $_ -Parent) -Leaf }),
    [System.StringComparer]::Ordinal
)

foreach ($agentPath in $agentPaths) {
    Test-DefinitionFrontmatter -Kind 'agent' -Path $agentPath.FullName `
        -ExpectedName $agentPath.BaseName -AllowedKeys @('name', 'description', 'model', 'tools')
}
foreach ($skillPath in $skillPaths) {
    $skillName = Split-Path (Split-Path $skillPath -Parent) -Leaf
    Test-DefinitionFrontmatter -Kind 'skill' -Path $skillPath `
        -ExpectedName $skillName -AllowedKeys @('name', 'description', 'license')
}

Test-ReferenceIntegrity -DefinitionPaths @(
    @($agentPaths | ForEach-Object FullName) +
    @($skillPaths)
) `
    -KnownAgents $knownAgents -KnownSkills $knownSkills
Test-Orchestration -KnownSkills $knownSkills
Test-ReadmeInventory -Path (Join-Path $RepositoryRoot 'README.md') `
    -AgentNames @($knownAgents) -SkillNames @($knownSkills)
Test-Json -Path (Join-Path $RepositoryRoot 'mcp-config.json')
Test-MutableRuntimeVersions -Paths @(
    (Join-Path $RepositoryRoot 'mcp-config.json'),
    (Join-Path $RepositoryRoot 'mcps/docker-compose.yml')
)
Test-DockerCompose -Path (Join-Path $RepositoryRoot 'mcps/docker-compose.yml')
Test-ReviewInvariants
Test-ReviewerCapabilityBoundary

Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host "✅ All $script:Passes configuration checks passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $($script:Failures.Count) configuration checks failed; $script:Passes passed." -ForegroundColor Red
exit 1
