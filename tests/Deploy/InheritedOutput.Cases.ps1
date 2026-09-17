#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Test-InheritedOutputTimeout {
    param(
        $Fixture,
        [switch]$ThroughNativeWrapper,
        [ValidateRange(2000, 5000)][int]$TimeoutMilliseconds = 5000
    )

    $identityPath = Join-Path $Fixture.Root 'inherited-output-identities.json'
    $readyPath = Join-Path $Fixture.Root 'inherited-output-ready'
    $releasePath = Join-Path $Fixture.Root 'inherited-output-release'
    try {
        $capture = Invoke-FixtureModule -Fixture $Fixture -Script {
            param($Pwsh, $Probe, $Root, $IdentityPath, $ReadyPath, $ReleasePath, $ThroughNativeWrapper, $TimeoutMilliseconds)
            $parameters = @{
                FilePath = $Pwsh
                ArgumentList = @('-NoProfile', '-NonInteractive', '-File', $Probe, 'inherit-output', $IdentityPath, $ReadyPath, $ReleasePath)
                WorkingDirectory = $Root
                TimeoutMilliseconds = $TimeoutMilliseconds
                Description = 'Owned inherited-output timeout probe'
            }
            $record = [pscustomobject]@{ Result = $null; Failure = $null; ElapsedMilliseconds = 0L }
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $record.Result = if ($ThroughNativeWrapper) { Invoke-DeployNative @parameters } else { Start-DeployProcess @parameters }
            }
            catch { $record.Failure = $_ }
            finally {
                $clock.Stop()
                $record.ElapsedMilliseconds = $clock.ElapsedMilliseconds
            }
            $record
        } -ArgumentList @((Join-Path $PSHOME 'pwsh.exe'), (Join-Path $PSScriptRoot 'Native-Probe.ps1'), $Fixture.Root,
            $identityPath, $readyPath, $releasePath, [bool]$ThroughNativeWrapper, $TimeoutMilliseconds)

        Assert-True (Test-Path -LiteralPath $identityPath -PathType Leaf) 'Probe did not record ownership of its parent and descendant.'
        Assert-True (Test-Path -LiteralPath $readyPath -PathType Leaf) 'Descendant never confirmed its inherited output handles.'
        $identity = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($identityPath))
        $parent = Get-Process -Id $identity.Parent.Id -ErrorAction SilentlyContinue
        try { Assert-True ($null -eq $parent -or $parent.HasExited) 'Regression did not exercise the parent-already-exited path.' }
        finally { if ($parent) { $parent.Dispose() } }

        Assert-True ($capture.ElapsedMilliseconds -ge ($TimeoutMilliseconds - 100) -and
            $capture.ElapsedMilliseconds -lt ($TimeoutMilliseconds + 1500)) `
            "Inherited output ignored the ${TimeoutMilliseconds}ms total deadline: returned after $($capture.ElapsedMilliseconds)ms."
        if ($ThroughNativeWrapper) {
            Assert-True ($null -ne $capture.Failure -and $capture.Failure.Exception -is [System.TimeoutException] -and
                $capture.Failure.Exception.Data['ExitCode'] -eq 124) 'Inherited output timeout did not propagate as timeout exit 124.'
            Assert-True ($capture.Failure.Exception.Message -notmatch 'owned descendant') 'Timeout diagnostic leaked partial native output.'
        }
        else {
            Assert-True ($null -eq $capture.Failure -and $null -ne $capture.Result -and $capture.Result.TimedOut) `
                'Incomplete inherited streams were reported as successful native completion.'
            Assert-True ($null -eq $capture.Result.ExitCode -and $capture.Result.Output -eq '') 'Stream timeout returned success-shaped status or partial output.'
        }
        $child = Get-Process -Id $identity.Child.Id -ErrorAction SilentlyContinue
        try {
            Assert-True ($null -ne $child -and -not $child.HasExited -and
                $child.StartTime.ToUniversalTime().Ticks -eq $identity.Child.StartTicks) 'Inherited streams were not held open by the owned descendant at timeout.'
        }
        finally { if ($child) { $child.Dispose() } }
        [pscustomobject]@{
            EntryPoint = $(if ($ThroughNativeWrapper) { 'Invoke-DeployNative' } else { 'Start-DeployProcess' })
            ElapsedMilliseconds = $capture.ElapsedMilliseconds
            TimedOut = $true
            ParentExited = $true
        }
    }
    finally {
        [System.IO.File]::WriteAllText($releasePath, '')
        if (Test-Path -LiteralPath $identityPath -PathType Leaf) {
            $identity = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($identityPath))
            foreach ($owned in @($identity.Child, $identity.Parent)) {
                $process = Get-Process -Id $owned.Id -ErrorAction SilentlyContinue
                if ($null -eq $process) { continue }
                try {
                    if ($process.StartTime.ToUniversalTime().Ticks -ne $owned.StartTicks) {
                        throw "Refusing to stop a reused, unowned PID: $($owned.Id)"
                    }
                    if (-not $process.HasExited) { Stop-Process -Id $owned.Id -Force -ErrorAction Stop }
                    if (-not $process.WaitForExit(1000)) { throw "Owned probe PID did not exit during bounded cleanup: $($owned.Id)" }
                }
                finally { $process.Dispose() }
            }
        }
    }
}
