#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$script:OwnedContexts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

function New-IsolatedProcessContext {
    [CmdletBinding()]
    param()

    $root = Join-Path ([IO.Path]::GetTempPath()) ('npcc-process-' + [guid]::NewGuid().ToString('N'))
    # Read-only preview probes still need real, disposable process infrastructure.
    $null = New-Item -ItemType Directory -Path $root -WhatIf:$false -Confirm:$false
    $null = $script:OwnedContexts.Add($root)
    try {
        foreach ($directory in @('home', 'config', 'cache', 'data', 'state', 'temp', 'hooks', 'templates')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $directory) -WhatIf:$false -Confirm:$false
        }
        $emptyConfig = Join-Path $root 'empty.config'
        [IO.File]::WriteAllBytes($emptyConfig, [byte[]]@())
        [pscustomobject]@{
            Root = $root
            Home = Join-Path $root 'home'
            Temp = Join-Path $root 'temp'
            EmptyConfig = $emptyConfig
            Hooks = Join-Path $root 'hooks'
        }
    }
    catch {
        Remove-IsolatedProcessContext -Context ([pscustomobject]@{ Root = $root })
        throw
    }
}

function Remove-IsolatedProcessContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    if (-not $script:OwnedContexts.Contains($Context.Root)) {
        throw "Refusing cleanup of an unowned process context: $($Context.Root)"
    }
    if (Test-Path -LiteralPath $Context.Root) {
        $item = Get-Item -LiteralPath $Context.Root -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing recursive cleanup of a replaced, linked context: $($Context.Root)"
        }
        Remove-Item -LiteralPath $Context.Root -Recurse -Force -WhatIf:$false -Confirm:$false
    }
    $null = $script:OwnedContexts.Remove($Context.Root)
}

function Invoke-IsolatedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowEmptyCollection()][byte[]]$InputBytes = @(),
        [hashtable]$Environment = @{},
        [switch]$AllowFailure
    )

    if (-not $script:OwnedContexts.Contains($Context.Root)) {
        throw "Process context is not owned by this module: $($Context.Root)"
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        $start.ArgumentList.Add($argument)
    }

    # -C alone does not override inherited repository, index, or config controls.
    foreach ($key in @($start.Environment.Keys)) {
        if ($key -like 'GIT_*') {
            $null = $start.Environment.Remove($key)
        }
    }
    $controlledEnvironment = @{
        HOME = $Context.Home
        USERPROFILE = $Context.Home
        HOMEDRIVE = [IO.Path]::GetPathRoot($Context.Home).TrimEnd('\')
        HOMEPATH = $Context.Home.Substring([IO.Path]::GetPathRoot($Context.Home).Length - 1)
        XDG_CONFIG_HOME = Join-Path $Context.Root 'config'
        XDG_CACHE_HOME = Join-Path $Context.Root 'cache'
        XDG_DATA_HOME = Join-Path $Context.Root 'data'
        XDG_STATE_HOME = Join-Path $Context.Root 'state'
        APPDATA = Join-Path $Context.Root 'config'
        LOCALAPPDATA = Join-Path $Context.Root 'data'
        COPILOT_HOME = Join-Path $Context.Home '.copilot'
        GH_CONFIG_DIR = Join-Path $Context.Root 'config'
        DOCKER_CONFIG = Join-Path $Context.Root 'config'
        DOTNET_CLI_HOME = $Context.Home
        NPM_CONFIG_USERCONFIG = $Context.EmptyConfig
        NPM_CONFIG_CACHE = Join-Path $Context.Root 'cache'
        TEMP = $Context.Temp
        TMP = $Context.Temp
        TMPDIR = $Context.Temp
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_CONFIG_SYSTEM = $Context.EmptyConfig
        GIT_CONFIG_GLOBAL = $Context.EmptyConfig
        GIT_ATTR_NOSYSTEM = '1'
        GIT_TERMINAL_PROMPT = '0'
        GIT_OPTIONAL_LOCKS = '0'
        GIT_NO_REPLACE_OBJECTS = '1'
        GIT_PAGER = 'cat'
    }
    $gitConfig = [ordered]@{
        'core.hooksPath' = $Context.Hooks
        'core.fsmonitor' = 'false'
        'core.untrackedCache' = 'false'
        'core.attributesFile' = $Context.EmptyConfig
        'commit.gpgSign' = 'false'
        'tag.gpgSign' = 'false'
        'init.templateDir' = (Join-Path $Context.Root 'templates')
    }
    $controlledEnvironment.GIT_CONFIG_COUNT = [string]$gitConfig.Count
    $index = 0
    foreach ($entry in $gitConfig.GetEnumerator()) {
        $controlledEnvironment["GIT_CONFIG_KEY_$index"] = $entry.Key
        $controlledEnvironment["GIT_CONFIG_VALUE_$index"] = $entry.Value
        $index++
    }
    foreach ($entry in $controlledEnvironment.GetEnumerator()) {
        $start.Environment[$entry.Key] = $entry.Value
    }
    # Explicit overrides are for a captured index or an isolated fault fixture,
    # never a copy of the caller's environment.
    foreach ($entry in $Environment.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            $null = $start.Environment.Remove($entry.Key)
        }
        else {
            $start.Environment[$entry.Key] = [string]$entry.Value
        }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $stdout = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) {
            throw "Cannot start native process '$FilePath'."
        }
        $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $null = $outputTask.GetAwaiter().GetResult()
        $stderr = $errorTask.GetAwaiter().GetResult()
        $bytes = $stdout.ToArray()
        $result = [pscustomobject]@{
            ExitCode = $process.ExitCode
            Bytes = $bytes
            Stdout = [Text.Encoding]::UTF8.GetString($bytes)
            Stderr = $stderr
            Output = [Text.Encoding]::UTF8.GetString($bytes) + $stderr
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "Native process '$FilePath' failed with exit $($result.ExitCode): $($result.Output)"
        }
        $result
    }
    finally {
        $stdout.Dispose()
        $process.Dispose()
    }
}

Export-ModuleMember -Function New-IsolatedProcessContext, Remove-IsolatedProcessContext, Invoke-IsolatedProcess
