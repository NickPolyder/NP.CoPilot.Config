#Requires -Version 7.0
<#
.SYNOPSIS
    Validates structural invariants for the Copilot configuration repository.

.DESCRIPTION
    Checks the supported on-disk configuration domain, including hidden and
    ignored definitions, without following links. Uses the strict repository
    YAML subset and runtime-reference policy documented in scripts\README.md.
    This is not a full YAML parser or a Copilot runtime compatibility test.
#>

[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),

    [switch]$SkipDockerCompose
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ConfigurationParsing.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'IsolatedProcess.psm1') -ErrorAction Stop

$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Passes = 0
$script:FrontmatterCache = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

$repositoryModels = [System.Collections.Generic.HashSet[string]]::new(
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
        Pattern = '(?s)New-GitReviewCandidate.*New-GitTreeSnapshot'
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

    if ($script:FrontmatterCache.ContainsKey($Path)) { return $script:FrontmatterCache[$Path] }
    try {
        $content = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    }
    catch {
        Add-Failure "$Path cannot be read as definition text: $($_.Exception.Message)"
        return $null
    }
    $match = [regex]::Match($content, '\A---\r?\n(?<frontmatter>.*?)\r?\n---(?:\r?\n|\z)', 'Singleline')

    if (-not $match.Success) {
        Add-Failure "$Path does not start with a closed YAML frontmatter block."
        return $null
    }

    try {
        $values = ConvertFrom-RepositoryYaml -Text $match.Groups['frontmatter'].Value -SourceName $Path
        $frontmatter = [pscustomobject]@{
            Content = $content
            Values = $values
        }
        $script:FrontmatterCache.Add($Path, $frontmatter)
        $frontmatter
    }
    catch {
        Add-Failure "$Path has invalid repository YAML frontmatter: $($_.Exception.Message)"
        return $null
    }
}

function Test-RequiredMetadataString {
    param(
        [Parameter(Mandatory)]$Frontmatter,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $Frontmatter.Values.ContainsKey($Key)) {
        Add-Failure "$Path has no $Key frontmatter value."
        return $false
    }
    $value = $Frontmatter.Values[$Key]
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        Add-Failure "$Path frontmatter '$Key' must be a nonempty string."
        return $false
    }
    return $true
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

    foreach ($key in $frontmatter.Values.Keys) {
        if ($key -cnotin $AllowedKeys) {
            Add-Failure "$Path uses unsupported $Kind frontmatter key '$key'."
        }
    }
    $null = Test-RequiredMetadataString -Frontmatter $frontmatter -Path $Path -Key 'description'
    if (Test-RequiredMetadataString -Frontmatter $frontmatter -Path $Path -Key 'name') {
        $actualName = $frontmatter.Values['name']
        if ($actualName -cne $ExpectedName) {
            Add-Failure "$Path declares name '$actualName' but its expected name is '$ExpectedName'."
        }
        if ($actualName -cnotmatch '^[a-z][a-z0-9-]*$') {
            Add-Failure "$Path name '$actualName' is outside the repository's lowercase kebab-case policy."
        }
    }
    if ($frontmatter.Values.ContainsKey('license')) {
        $null = Test-RequiredMetadataString -Frontmatter $frontmatter -Path $Path -Key 'license'
    }
    if ($frontmatter.Values.ContainsKey('tools')) {
        $tools = $frontmatter.Values['tools']
        if ($tools -isnot [array] -or $tools.Count -eq 0 -or @($tools | Where-Object {
            $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_)
        }).Count -gt 0) {
            Add-Failure "$Path frontmatter 'tools' must be a nonempty string sequence."
        }
    }

    if ($Kind -eq 'agent') {
        if (Test-RequiredMetadataString -Frontmatter $frontmatter -Path $Path -Key 'model') {
            $model = $frontmatter.Values['model']
            if (-not $repositoryModels.Contains($model)) {
                Add-Failure "$Path uses model '$model' outside the repository model policy (not a CLI support claim)."
            }
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
        Write-Pass 'README inventory includes every on-disk agent and skill in the supported domain.'
    }
}

function Test-ImageReference {
    param($Reference, [string]$Location)

    if ($Reference -isnot [string] -or [string]::IsNullOrWhiteSpace($Reference)) {
        Add-Failure "$Location must contain a nonempty image reference."
        return
    }
    $parts = $Reference.Split('@')
    $nameAndTag = $parts[0]
    $tag = ''
    $colon = $nameAndTag.LastIndexOf(':')
    if ($colon -gt $nameAndTag.LastIndexOf('/')) {
        $tag = $nameAndTag.Substring($colon + 1)
        $nameAndTag = $nameAndTag.Substring(0, $colon)
    }
    if ($parts.Count -gt 2 -or $nameAndTag -cnotmatch '^(?:[a-z0-9.-]+(?::[0-9]+)?/)?[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$' -or
        ($colon -gt $parts[0].LastIndexOf('/') -and $tag -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')) {
        Add-Failure "$Location has an unsupported or malformed image reference '$Reference'."
        return
    }
    if ($parts.Count -eq 2) {
        if ($parts[1] -cnotmatch '^sha256:[0-9a-f]{64}$') {
            Add-Failure "$Location requires a complete SHA-256 image digest, not '$Reference'."
        }
        return
    }
    if ($tag -cnotmatch '^v?(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:[-._][A-Za-z0-9][A-Za-z0-9_.-]*)?$') {
        Add-Failure "$Location requires an explicit three-part image version or SHA-256 digest; untagged/moving reference '$Reference' is not approved."
    }
}

function Test-PackageReference {
    param([string]$Reference, [string]$ServerName, [string]$Location)

    if ($ServerName -ceq 'playwright' -and $Reference -ceq '@playwright/mcp@latest') {
        Add-Warning "$Location intentionally uses @playwright/mcp@latest under the documented user-approved waiver."
        return
    }
    if ($Reference -cnotmatch '^(?:@[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*|[a-z0-9][a-z0-9._-]*)@(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-(?<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
        Add-Failure "$Location requires an exact package version; unversioned/range/moving reference '$Reference' is not approved."
        return
    }
    foreach ($identifier in ($Matches.prerelease -split '\.')) {
        if ($identifier -match '^0[0-9]+$') {
            Add-Failure "$Location has an invalid semantic-version prerelease '$Reference'."
        }
    }
}

function Test-LocalRuntimeArguments {
    param([string]$Command, [string[]]$Arguments, [string]$ServerName, [string]$Location)

    if ($Command -cin @('docker', 'docker.exe')) {
        if ($Arguments.Count -eq 0 -or $Arguments[0] -cne 'run') {
            Add-Failure "$Location supports only explicit 'docker run' runtime arguments."
            return
        }
        $valueFlags = @('-e', '--env', '--env-file', '-p', '--publish', '-v', '--volume', '--mount',
            '--network', '--name', '-u', '--user', '-w', '--workdir', '--entrypoint', '--platform', '--label')
        for ($i = 1; $i -lt $Arguments.Count; $i++) {
            $argument = $Arguments[$i]
            if ($argument -ceq '--') { $i++; break }
            if (-not $argument.StartsWith('-')) { break }
            if ($argument -cin @('-i', '--interactive', '--rm', '--init', '-t', '--tty', '-it')) { continue }
            $flag = $argument.Split('=', 2)
            if ($flag[0] -cnotin $valueFlags) {
                Add-Failure "$Location uses unsupported Docker option '$argument'; image discovery cannot be established."
                return
            }
            if ($flag.Count -eq 1) {
                $i++
                if ($i -ge $Arguments.Count -or [string]::IsNullOrEmpty($Arguments[$i])) {
                    Add-Failure "$Location has a Docker option without its required value."
                    return
                }
            }
            elseif (-not $flag[1]) {
                Add-Failure "$Location has an empty Docker option value."
                return
            }
        }
        if ($i -ge $Arguments.Count) { Add-Failure "$Location is missing its Docker runtime image."; return }
        Test-ImageReference -Reference $Arguments[$i] -Location "$Location image"
        return
    }
    if ($Command -cin @('npx', 'npx.cmd', 'npx.exe')) {
        $packages = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            $argument = $Arguments[$i]
            if ($argument -ceq '--') { $i++; break }
            if (-not $argument.StartsWith('-')) { break }
            if ($argument -cin @('-y', '--yes', '--no', '--no-install', '-q', '--quiet')) { continue }
            $flag = $argument.Split('=', 2)
            if ($flag[0] -cnotin @('-p', '--package')) {
                Add-Failure "$Location uses unsupported npx option '$argument'; package discovery cannot be established."
                return
            }
            if ($flag.Count -eq 2 -and $flag[1]) { $packages.Add($flag[1]) }
            elseif ($flag.Count -eq 1 -and ++$i -lt $Arguments.Count -and $Arguments[$i]) { $packages.Add($Arguments[$i]) }
            else { Add-Failure "$Location has an npx package option without its required value."; return }
        }
        if ($packages.Count -eq 0) {
            if ($i -ge $Arguments.Count) { Add-Failure "$Location is missing its npx runtime package."; return }
            $packages.Add($Arguments[$i])
        }
        foreach ($package in $packages) {
            Test-PackageReference -Reference $package -ServerName $ServerName -Location "$Location package"
        }
        return
    }
    Add-Failure "$Location uses unsupported local runtime launcher '$Command'; explicit runtime versions cannot be established."
}

function Test-MutableRuntimeVersions {
    param($McpConfig, $Compose)

    $failureCount = $script:Failures.Count
    if ($McpConfig -isnot [Collections.IDictionary] -or $McpConfig['mcpServers'] -isnot [Collections.IDictionary] -or
        $McpConfig['mcpServers'].Count -eq 0) {
        Add-Failure 'mcp-config.json must define a nonempty mcpServers object for runtime validation.'
    }
    else {
        foreach ($entry in $McpConfig['mcpServers'].GetEnumerator()) {
            $location = "mcp-config.json mcpServers.$($entry.Key)"
            $server = $entry.Value
            if ($server -isnot [Collections.IDictionary]) { Add-Failure "$location must be an object."; continue }
            if ($server['type'] -cin @('http', 'sse')) { continue }
            if ($server['type'] -cne 'local' -or $server['command'] -isnot [string] -or
                $server['args'] -isnot [array] -or @($server['args'] | Where-Object { $_ -isnot [string] }).Count -gt 0) {
                Add-Failure "$location requires a local type, command string, and string-array args for runtime validation."
                continue
            }
            Test-LocalRuntimeArguments -Command $server['command'] -Arguments $server['args'] -ServerName $entry.Key -Location $location
        }
    }
    if ($Compose -isnot [Collections.IDictionary] -or $Compose['services'] -isnot [Collections.IDictionary] -or
        $Compose['services'].Count -eq 0) {
        Add-Failure 'mcps\docker-compose.yml must define a nonempty services mapping with explicit runtime images.'
    }
    else {
        if ($Compose.ContainsKey('include')) { Add-Failure 'Compose include resolution is outside the supported static runtime domain.' }
        foreach ($entry in $Compose['services'].GetEnumerator()) {
            $location = "mcps\docker-compose.yml services.$($entry.Key)"
            $service = $entry.Value
            if ($service -isnot [Collections.IDictionary]) { Add-Failure "$location must be a mapping."; continue }
            foreach ($unsupported in @('extends', 'build', 'env_file')) {
                if ($service.ContainsKey($unsupported)) {
                    Add-Failure "$location uses unsupported '$unsupported' resolution in the static runtime domain."
                }
            }
            Test-ImageReference -Reference $service['image'] -Location "$location.image"
        }
    }
    if ($script:Failures.Count -eq $failureCount) {
        Write-Pass 'Runtime MCP definitions use explicit image versions/digests and exact package versions or documented waivers.'
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

        $parsed = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        Write-Pass "$Path contains valid JSON."
        return $parsed
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

    $context = New-IsolatedProcessContext
    try {
        [IO.File]::Copy($Path, (Join-Path $context.Root 'compose.yml'))
        $result = Invoke-IsolatedProcess -Context $context -FilePath (Get-Command docker -CommandType Application).Source `
            -WorkingDirectory $context.Root `
            -ArgumentList @('compose', '--env-file', 'empty.config', '-f', 'compose.yml', 'config', '--no-interpolate', '--quiet') -AllowFailure
        if ($result.ExitCode -ne 0) {
            Add-Failure "$Path failed docker compose config validation (exit $($result.ExitCode)): $($result.Output)"
            return
        }
        Write-Pass "$Path passes docker compose config validation."
    }
    finally {
        Remove-IsolatedProcessContext -Context $context
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

    $tools = $frontmatter.Values['tools']
    if (-not $frontmatter.Values.ContainsKey('tools')) {
        Add-Failure 'agents/code-reviewer.md is missing its reviewer tools list.'
    }
    elseif ($tools -is [array] -and @($tools | Where-Object { $_ -isnot [string] }).Count -eq 0) {
        $actualTools = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$tools,
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
        if ($tools.Count -ne $reviewerExpectedTools.Count) {
            Add-Failure 'agents/code-reviewer.md must declare each required reviewer tool exactly once.'
        }
    }
    else {
        Add-Failure 'agents/code-reviewer.md must declare a valid reviewer tools string sequence.'
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

function Assert-PhysicalConfigPath {
    param([string]$Path, [switch]$AllowMissing)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $current = [IO.Path]::GetPathRoot($fullPath)
    $parts = @('') + @($fullPath.Substring($current.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($part in $parts) {
        if ($part) { $current = Join-Path $current $part }
        try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] {
            if ($AllowMissing) { return $false }
            throw
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked configuration input or ancestor is unsupported; contents were not followed: $current"
        }
    }
    return $true
}

function Get-ConfigurationInputs {
    $null = Assert-PhysicalConfigPath -Path $RepositoryRoot
    $agentPaths = [Collections.Generic.List[object]]::new()
    $skillPaths = [Collections.Generic.List[string]]::new()
    foreach ($directory in @('agents', 'skills')) {
        $path = Join-Path $RepositoryRoot $directory
        if (-not (Assert-PhysicalConfigPath -Path $path -AllowMissing)) {
            Add-Failure "Missing required definition directory '$directory'."
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Definition root '$directory' is not a directory." }
        foreach ($item in Get-ChildItem -LiteralPath $path -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked definition is unsupported; contents were not followed: $($item.FullName)"
            }
            if ($directory -eq 'agents' -and $item.PSIsContainer -and $item.Name -notlike '*.md') {
                throw "Nested agent definition directories are unsupported; contents were not traversed: $($item.FullName)"
            }
            if ($directory -eq 'agents' -and $item.Name -like '*.md') {
                if ($item.PSIsContainer) { throw "Agent definition is a directory, not a file: $($item.FullName)" }
                $agentPaths.Add($item)
            }
            elseif ($directory -eq 'skills' -and $item.PSIsContainer) {
                $skillPath = Join-Path $item.FullName 'SKILL.md'
                if (-not (Assert-PhysicalConfigPath -Path $skillPath -AllowMissing)) {
                    Add-Failure "Skill directory '$($item.Name)' is missing SKILL.md."
                    continue
                }
                if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { throw "Skill definition is not a regular file: $skillPath" }
                $skillPaths.Add($skillPath)
            }
        }
    }
    foreach ($relative in @('README.md', 'mcp-config.json', 'mcps\docker-compose.yml')) {
        $path = Join-Path $RepositoryRoot $relative
        if (-not (Assert-PhysicalConfigPath -Path $path -AllowMissing)) {
            Add-Failure "Missing required validator input '$relative'."
        }
        elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Validator input '$relative' must be a regular file."
        }
    }
    [pscustomobject]@{ AgentPaths = $agentPaths.ToArray(); SkillPaths = $skillPaths.ToArray() }
}

Write-Host ''
Write-Host '🔍 Validating Copilot configuration...' -ForegroundColor Cyan

try {
    $inputs = Get-ConfigurationInputs
}
catch {
    Add-Failure "Configuration input-domain violation: $($_.Exception.Message)"
    Write-Host "❌ $($script:Failures.Count) configuration checks failed; $script:Passes passed." -ForegroundColor Red
    exit 1
}
$agentPaths = @($inputs.AgentPaths)
$skillPaths = @($inputs.SkillPaths)

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
if (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'README.md') -PathType Leaf) {
    Test-ReadmeInventory -Path (Join-Path $RepositoryRoot 'README.md') `
        -AgentNames @($knownAgents) -SkillNames @($knownSkills)
}
$mcpConfig = Test-Json -Path (Join-Path $RepositoryRoot 'mcp-config.json')
$composePath = Join-Path $RepositoryRoot 'mcps\docker-compose.yml'
$compose = $null
try {
    $composeText = [IO.File]::ReadAllText($composePath, [Text.UTF8Encoding]::new($false, $true))
    $compose = ConvertFrom-RepositoryYaml -Text $composeText -SourceName $composePath
}
catch {
    Add-Failure "$composePath is not valid supported repository YAML: $($_.Exception.Message)"
}
$runtimeFailureCount = $script:Failures.Count
Test-MutableRuntimeVersions -McpConfig $mcpConfig -Compose $compose
if ($script:Failures.Count -eq $runtimeFailureCount -and $null -ne $compose) {
    Test-DockerCompose -Path $composePath
}
Test-ReviewInvariants
Test-ReviewerCapabilityBoundary

Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host "✅ All $script:Passes configuration checks passed." -ForegroundColor Green
    exit 0
}

Write-Host "❌ $($script:Failures.Count) configuration checks failed; $script:Passes passed." -ForegroundColor Red
exit 1
