#Requires -Version 5.1

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
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [AllowEmptyCollection()][byte[]]$InputBytes = @(),
        [hashtable]$Environment = @{},
        [scriptblock]$StandardOutputHandler,
        [ValidateRange(1, 2147483)][int]$TimeoutSeconds = 300,
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
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        foreach ($argument in $ArgumentList) {
            $start.ArgumentList.Add($argument)
        }
    }
    else {
        # .NET Framework has no ArgumentList; escape Windows native argv, not shell text.
        $quotedArguments = foreach ($argument in $ArgumentList) {
            $escaped = [regex]::Replace($argument, '(\\*)"', '$1$1\"')
            '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
        }
        $start.Arguments = $quotedArguments -join ' '
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

    if (-not ('NPConfig.IsolatedProcessRuntime' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

namespace NPConfig {
    public static class IsolatedProcessRuntime {
        public sealed class Deadline {
            private readonly Stopwatch clock = Stopwatch.StartNew();
            private readonly int milliseconds;

            public Deadline(int seconds) { milliseconds = checked(seconds * 1000); }
            public int RemainingMilliseconds {
                get {
                    long remaining = milliseconds - clock.ElapsedMilliseconds;
                    if (remaining <= 0) { throw new TimeoutException("Native process deadline expired."); }
                    return (int)remaining;
                }
            }
            public bool Expired { get { return clock.ElapsedMilliseconds >= milliseconds; } }
            public void Wait(Task task) {
                if (!task.Wait(RemainingMilliseconds)) {
                    throw new TimeoutException("Native process deadline expired.");
                }
            }
        }

        private sealed class DeadlineReadStream : Stream {
            private readonly Stream input;
            private readonly Deadline deadline;

            public DeadlineReadStream(Stream input, Deadline deadline) {
                this.input = input;
                this.deadline = deadline;
            }
            public override int Read(byte[] buffer, int offset, int count) {
                Task<int> read = input.ReadAsync(buffer, offset, count);
                deadline.Wait(read);
                return read.GetAwaiter().GetResult();
            }
            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return false; } }
            public override long Length { get { throw new NotSupportedException(); } }
            public override long Position {
                get { throw new NotSupportedException(); }
                set { throw new NotSupportedException(); }
            }
            public override void Flush() { }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        }

        public static Deadline CreateDeadline(int seconds) { return new Deadline(seconds); }
        public static Stream CreateOutputStream(Stream input, Deadline deadline) {
            return new BufferedStream(new DeadlineReadStream(input, deadline), 65536);
        }
        public static async Task WriteAndFlushAsync(Stream stream, byte[] bytes) {
            await stream.WriteAsync(bytes, 0, bytes.Length).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }
    }
}
'@
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $stdout = [IO.MemoryStream]::new()
    $reader = $null
    $started = $false
    $deadline = [NPConfig.IsolatedProcessRuntime]::CreateDeadline($TimeoutSeconds)
    try {
        $started = $process.Start()
        if (-not $started) {
            throw "Cannot start native process '$FilePath'."
        }
        $errorTask = $process.StandardError.ReadToEndAsync()
        if ($StandardOutputHandler) {
            $reader = [NPConfig.IsolatedProcessRuntime]::CreateOutputStream($process.StandardOutput.BaseStream, $deadline)
            # Consume a known response count, not EOF: stdin closes after this handler.
            # Flush buffered pipe tails concurrently; waiting here can deadlock on stdout backpressure.
            $inputTask = [NPConfig.IsolatedProcessRuntime]::WriteAndFlushAsync($process.StandardInput.BaseStream, $InputBytes)
            $null = & $StandardOutputHandler $reader
            $outputTask = $reader.CopyToAsync($stdout)
        }
        else {
            $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
            $inputTask = [NPConfig.IsolatedProcessRuntime]::WriteAndFlushAsync($process.StandardInput.BaseStream, $InputBytes)
        }
        $deadline.Wait($inputTask)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($deadline.RemainingMilliseconds)) {
            throw "Native process '$FilePath' timed out after $TimeoutSeconds seconds."
        }
        $deadline.Wait($outputTask)
        $deadline.Wait($errorTask)
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
    catch {
        if ($deadline.Expired) {
            throw "Native process '$FilePath' timed out after $TimeoutSeconds seconds."
        }
        throw
    }
    finally {
        try {
            if ($started -and -not $process.HasExited) {
                if ($PSVersionTable.PSVersion.Major -ge 6) { $process.Kill($true) }
                else { $process.Kill() }
                if (-not $process.WaitForExit(5000)) {
                    throw "Native process '$FilePath' did not exit within 5 seconds after termination."
                }
            }
        }
        finally {
            if ($reader) { $reader.Dispose() }
            $stdout.Dispose()
            $process.Dispose()
        }
    }
}

Export-ModuleMember -Function New-IsolatedProcessContext, Remove-IsolatedProcessContext, Invoke-IsolatedProcess
