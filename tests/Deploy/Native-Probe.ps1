#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
switch ($args[0]) {
    'echo' {
        ConvertTo-Json -InputObject @{
            Arguments = @($args | Select-Object -Skip 1)
            Input = [Console]::In.ReadToEnd()
            Port = $env:SEARXNG_PORT
        } -Compress
    }
    'fail' {
        Write-Output 'private-looking-native-stdout'
        [Console]::Error.WriteLine('private-looking-native-stderr')
        exit 47
    }
    'sleep' {
        [System.IO.File]::WriteAllText($args[1], [string]$PID)
        Start-Sleep -Seconds 10
    }
    'inherit-output' {
        $identityPath, $readyPath, $releasePath = $args[1..3]
        $start = [System.Diagnostics.ProcessStartInfo]::new()
        $start.FileName = Join-Path $PSHOME 'pwsh.exe'
        $start.UseShellExecute = $false
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $PSCommandPath, 'hold-output', $readyPath, $releasePath)) {
            $start.ArgumentList.Add($argument)
        }
        $child = [System.Diagnostics.Process]::Start($start)
        try {
            $parent = [System.Diagnostics.Process]::GetCurrentProcess()
            try {
                $identity = @{
                    Parent = @{ Id = $PID; StartTicks = $parent.StartTime.ToUniversalTime().Ticks }
                    Child = @{ Id = $child.Id; StartTicks = $child.StartTime.ToUniversalTime().Ticks }
                }
                [System.IO.File]::WriteAllText($identityPath, (ConvertTo-Json -InputObject $identity -Depth 3 -Compress))
            }
            finally { $parent.Dispose() }
        }
        finally { $child.Dispose() }
        exit 0
    }
    'hold-output' {
        [Console]::Out.WriteLine('owned descendant stdout')
        [Console]::Error.WriteLine('owned descendant stderr')
        [System.IO.File]::WriteAllText($args[1], 'inherited output handles are open')
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while ($clock.ElapsedMilliseconds -lt 15000 -and -not [System.IO.File]::Exists($args[2])) {
            Start-Sleep -Milliseconds 25
        }
    }
    default { throw 'Unknown isolated native probe.' }
}
