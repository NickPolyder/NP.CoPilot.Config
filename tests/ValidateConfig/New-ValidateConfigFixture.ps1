#Requires -Version 7.0
<#
.SYNOPSIS
    Builds isolated, disposable fixture trees for Validate-Config.ps1 tests.
.DESCRIPTION
    No side effects outside $env:TEMP. Never touches the repository's real
    agents/skills directories or ~/.copilot. Callers must remove the
    returned path when done (Remove-FixtureRoot / try-finally).
#>

$ErrorActionPreference = 'Stop'

# Every skill name referenced by Validate-Config.ps1's hardcoded $orchestration
# map. A "fully green" fixture must include stub SKILL.md files for all of
# these, or Test-Orchestration will fail on missing nodes.
$script:OrchestrationSkillNames = @(
    'prd-workflow', 'codebase-research', 'feature-design-doc',
    'task-breakdown', 'implementation-runner',
    'dependency-audit', 'dependency-audit-report', 'dependency-upgrade-execution',
    'test-gap-analysis', 'test-gap-audit', 'test-gap-fill',
    'git-commit-review', 'full-code-review'
)

function New-FixtureRoot {
    <#
    .SYNOPSIS
        Creates a fresh temp directory. Caller is responsible for cleanup.
    #>
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("npcc-validate-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path | Out-Null
    $path
}

function Remove-FixtureRoot {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function New-AgentFile {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaseName,
        [string]$Name = $BaseName,
        [string]$Description = 'Fixture agent used for regression testing.',
        [string]$Model = 'claude-sonnet-5',
        [string]$Body = '# Fixture Agent',
        [string[]]$ExtraFrontmatterLines = @(),
        [switch]$OmitModel,
        [switch]$OmitName
    )

    $agentsDir = Join-Path $Root 'agents'
    New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    if (-not $OmitName) { $lines.Add("name: $Name") }
    $lines.Add("description: $Description")
    if (-not $OmitModel) { $lines.Add("model: $Model") }
    foreach ($extra in $ExtraFrontmatterLines) { $lines.Add($extra) }
    $lines.Add('---')
    $lines.Add('')
    $lines.Add($Body)

    $content = ($lines -join "`n")
    Set-Content -Path (Join-Path $agentsDir "$BaseName.md") -Value $content -Encoding utf8 -NoNewline
}

function New-SkillFile {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$DirName,
        [string]$Name = $DirName,
        [string]$Description = 'Fixture skill used for regression testing.',
        [string]$License = 'MIT',
        [string]$Body = '# Fixture Skill',
        [string[]]$ExtraFrontmatterLines = @(),
        [switch]$OmitName
    )

    $skillDir = Join-Path $Root "skills\$DirName"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    if (-not $OmitName) { $lines.Add("name: $Name") }
    $lines.Add("description: $Description")
    $lines.Add("license: $License")
    foreach ($extra in $ExtraFrontmatterLines) { $lines.Add($extra) }
    $lines.Add('---')
    $lines.Add('')
    $lines.Add($Body)

    $content = ($lines -join "`n")
    Set-Content -Path (Join-Path $skillDir 'SKILL.md') -Value $content -Encoding utf8 -NoNewline
}

function New-BaselineFixture {
    <#
    .SYNOPSIS
        Builds a fully green fixture: passes every Validate-Config.ps1 check
        (with -SkipDockerCompose). Callers mutate the returned tree to
        construct negative/edge/boundary cases for a single behavior.
    #>
    $root = New-FixtureRoot

    New-AgentFile -Root $root -BaseName 'sample-agent'
    New-AgentFile -Root $root -BaseName 'sample-agent-two'

    $compliantReviewerBody = @'
# Code Reviewer Fixture

## Rules

- Do not create reports, directories, or any other artifacts.
'@

    New-AgentFile -Root $root -BaseName 'code-reviewer' -Body $compliantReviewerBody `
        -ExtraFrontmatterLines @('tools:', '  - read', '  - search')

    $gitCommitReviewBody = @'
# git-commit-review

Uses git write-tree to build a tree object, then git archive --format=tar
to materialize an index-only snapshot for review.

If the snapshot cannot be materialized, stop before launching any reviewer.

This workflow owns report consolidation and persistence.
'@

    $fullCodeReviewBody = @'
# full-code-review

Runs only when the user explicitly requests an exhaustive review.

This workflow owns report consolidation and persistence.
'@

    foreach ($skillName in $script:OrchestrationSkillNames) {
        $body = switch ($skillName) {
            'git-commit-review' { $gitCommitReviewBody }
            'full-code-review' { $fullCodeReviewBody }
            default { "# $skillName`n`nFixture stub body." }
        }
        New-SkillFile -Root $root -DirName $skillName -Body $body
    }

    $readmeLines = @('# Fixture', '', '## Agents', 'sample-agent.md', 'sample-agent-two.md', 'code-reviewer.md', '', '## Skills')
    $readmeLines += ($script:OrchestrationSkillNames | ForEach-Object { "$_/" })
    Set-Content -Path (Join-Path $root 'README.md') -Value ($readmeLines -join "`n") -Encoding utf8 -NoNewline

    $mcpConfig = '{"mcpServers":{"example":{"type":"local","command":"docker","args":["run","-i","--rm","example/image:1.2.3"]}}}'
    Set-Content -Path (Join-Path $root 'mcp-config.json') -Value $mcpConfig -Encoding utf8 -NoNewline

    New-Item -ItemType Directory -Path (Join-Path $root 'mcps') -Force | Out-Null
    $compose = "services:`n  example:`n    image: example/image:1.2.3`n"
    Set-Content -Path (Join-Path $root 'mcps\docker-compose.yml') -Value $compose -Encoding utf8 -NoNewline

    $root
}
