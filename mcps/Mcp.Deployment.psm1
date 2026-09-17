#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Write-Status($Icon, $Message) {
    Write-Host "  $Icon $Message"
}

function Start-DeployProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [byte[]]$InputBytes,
        [string[]]$RemoveEnvironment = @(),
        [int]$TimeoutMilliseconds,
        [string]$Description
    )

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    foreach ($argument in $ArgumentList) { $start.ArgumentList.Add($argument) }
    foreach ($name in $RemoveEnvironment) { $null = $start.Environment.Remove($name) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw "Could not start native command for: $Description" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $inputError = $null
        if ($null -ne $InputBytes) {
            try {
                $write = $process.StandardInput.BaseStream.WriteAsync($InputBytes, 0, $InputBytes.Length)
                $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
                if (-not $write.Wait($remaining)) {
                    return [pscustomobject]@{ ExitCode = $null; Output = ''; TimedOut = $true }
                }
            }
            catch [System.AggregateException] { $inputError = $_.Exception }
            catch [System.IO.IOException] { $inputError = $_.Exception }
        }
        $process.StandardInput.Close()
        $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) {
            return [pscustomobject]@{ ExitCode = $null; Output = ''; TimedOut = $true }
        }
        $exitCode = $process.ExitCode
        # Descendants can retain stdout/stderr after the parent exits.
        $streams = [System.Threading.Tasks.Task]::WhenAll([System.Threading.Tasks.Task[]]@($stdout, $stderr))
        $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
        if (-not $streams.Wait($remaining) -or $clock.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            return [pscustomobject]@{ ExitCode = $null; Output = ''; TimedOut = $true }
        }
        $output = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($inputError -and $exitCode -eq 0) { throw "Could not deliver stdin for: $Description" }
        [pscustomobject]@{ ExitCode = $exitCode; Output = $output; TimedOut = $false }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) }
            catch [System.InvalidOperationException] {
                if (-not $process.HasExited) { throw }
            }
            $remaining = [Math]::Max(0, $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
            $null = $process.WaitForExit($remaining)
        }
        $process.Dispose()
    }
}

function Invoke-DeployNative {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [byte[]]$InputBytes,
        [string[]]$RemoveEnvironment = @(),
        [int]$TimeoutMilliseconds = 300000,
        [string]$Description
    )

    $result = Start-DeployProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory `
        -InputBytes $InputBytes -RemoveEnvironment $RemoveEnvironment -TimeoutMilliseconds $TimeoutMilliseconds -Description $Description
    if ($result.TimedOut) {
        $error = [System.TimeoutException]::new("$Description timed out. Native output is withheld to protect private configuration.")
        $error.Data['ExitCode'] = 124
        throw $error
    }
    if ($null -eq $result.ExitCode) { throw "$Description did not return a native exit status." }
    if ($result.ExitCode -ne 0) {
        $error = [System.InvalidOperationException]::new("$Description failed (native exit $($result.ExitCode)). Native output is withheld to protect private configuration.")
        $error.Data['ExitCode'] = [int]$result.ExitCode
        throw $error
    }
    [string]$result.Output
}

function ConvertTo-PosixCommand {
    param([string[]]$ArgumentList)
    $quoted = foreach ($argument in $ArgumentList) {
        if ($argument.Contains([char]0)) { throw 'Shell arguments cannot contain NUL.' }
        "'" + $argument.Replace("'", "'`"'`"'") + "'"
    }
    $quoted -join ' '
}

function Invoke-TargetShell {
    param(
        $Context,
        [string]$Script,
        [string[]]$ArgumentList = @(),
        [byte[]]$InputBytes,
        [string]$Description,
        [int]$TimeoutMilliseconds = $Context.CommandTimeoutMilliseconds
    )

    if ($Context.Mode -eq 'Remote') {
        # SSH adds a remote login-shell boundary; quote every token exactly once.
        $command = ConvertTo-PosixCommand (@('sh', '-c', $Script, 'np-mcp') + $ArgumentList)
        $nativeArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '--', $Context.SshTarget, $command)
        Invoke-DeployNative -FilePath 'ssh' -ArgumentList $nativeArgs -InputBytes $InputBytes `
            -TimeoutMilliseconds $TimeoutMilliseconds -Description $Description
    }
    elseif ($Context.Mode -eq 'WSL') {
        $nativeArgs = @()
        if ($Context.Distro) { $nativeArgs += @('--distribution', $Context.Distro) }
        $nativeArgs += @('--exec', 'sh', '-c', $Script, 'np-mcp') + $ArgumentList
        Invoke-DeployNative -FilePath 'wsl.exe' -ArgumentList $nativeArgs -InputBytes $InputBytes `
            -TimeoutMilliseconds $TimeoutMilliseconds -Description $Description
    }
    else { throw 'A target shell is only supported for Remote and WSL.' }
}

function Resolve-DeploymentPath {
    param($Context, [string]$Path)
    if ($Context.Mode -eq 'Local') {
        if ($Path -eq '~') { $Path = $HOME }
        elseif ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) { $Path = Join-Path $HOME $Path.Substring(2) }
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    $resolve = @'
set -eu
case "$1" in
  '~') path=$HOME ;;
  '~/'*) path=$HOME/${1#??} ;;
  /*) path=$1 ;;
  *) exit 2 ;;
esac
printf '%s' "$path"
'@
    $resolved = Invoke-TargetShell -Context $Context -Script $resolve -ArgumentList @($Path) -Description 'Resolve target directory'
    if (-not $resolved.StartsWith('/') -or $resolved -match '[\r\n]') { throw 'Target directory resolution did not return one absolute path.' }
    $resolved
}

function Join-DeploymentPath {
    param($Context, [string]$Child)
    if ($Context.Mode -eq 'Local') { return Join-Path $Context.Path $Child }
    $Context.Path.TrimEnd('/') + '/' + $Child.Replace('\', '/')
}

function Get-LocalDeploymentFile {
    param([string]$Path, [string]$Label, [switch]$ReadContent)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Exists = $false; Content = '' } }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "$Label must be a regular, non-linked file: $Path"
    }
    $content = if ($ReadContent) { [System.IO.File]::ReadAllText($Path) } else { '' }
    [pscustomobject]@{ Exists = $true; Content = $content }
}

function Get-DeploymentFile {
    param($Context, [string]$Path, [string]$Label, [switch]$ReadContent)
    if ($Context.Mode -eq 'Local') { return Get-LocalDeploymentFile -Path $Path -Label $Label -ReadContent:$ReadContent }
    $read = @'
set -eu
if [ -L "$1" ]; then exit 3
elif [ -f "$1" ]; then
  printf 'present\n'
  if [ "$2" = read ]; then cat -- "$1"; fi
elif [ -e "$1" ]; then exit 3
else printf 'missing\n'
fi
'@
    $action = if ($ReadContent) { 'read' } else { 'inspect' }
    $output = Invoke-TargetShell -Context $Context -Script $read -ArgumentList @($Path, $action) -Description "Inspect $Label"
    if ($output -eq "missing`n") { return [pscustomobject]@{ Exists = $false; Content = '' } }
    if (-not $output.StartsWith("present`n")) { throw "Invalid response while inspecting $Label; contents withheld." }
    [pscustomobject]@{ Exists = $true; Content = $output.Substring(8) }
}

function Test-DeploymentSecret {
    param([AllowEmptyString()][string]$Value)
    $Value -cmatch '^[0-9a-fA-F]{64}$' -and $Value -cnotmatch '^(.)\1+$'
}

function Read-DeploymentEnvironment {
    param([AllowEmptyString()][string]$Content, [string]$Label, [bool]$RequireSecret = $true)
    $values = @{}
    foreach ($line in ($Content.TrimStart([char]0xfeff) -split '\r?\n')) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -cnotmatch '^\s*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=(.*)$') {
            throw "$Label contains unsupported .env syntax. Use single-line literal assignments; contents withheld."
        }
        $name, $value = $Matches[1], $Matches[2].Trim()
        if (@('SEARXNG_SECRET', 'SEARXNG_PORT', 'SEARXNG_HOSTNAME') -cnotcontains $name) { continue }
        if ($values.ContainsKey($name)) { throw "$Label contains duplicate $name assignments; contents withheld." }
        if ($value -match "^'([^']*)'\s*(?:#.*)?$" -or $value -match '^"([^"]*)"\s*(?:#.*)?$') {
            $value = $Matches[1]
        }
        else { $value = ($value -replace '\s+#.*$', '').Trim() }
        $values[$name] = $value
    }
    $secret = [string]$values['SEARXNG_SECRET']
    if ($RequireSecret -and -not (Test-DeploymentSecret $secret)) {
        throw "$Label requires SEARXNG_SECRET: 64 hexadecimal characters, not a placeholder/repeated character. Initialize it privately; values are never printed."
    }
    $hostname = if ($values['SEARXNG_HOSTNAME']) { $values['SEARXNG_HOSTNAME'] } else { 'localhost' }
    $port = if ($values['SEARXNG_PORT']) { $values['SEARXNG_PORT'] } else { '8080' }
    if ($hostname -notmatch '^(?:[A-Za-z0-9][A-Za-z0-9.-]*|\[[0-9a-fA-F:]+\])$') {
        throw "$Label has an invalid literal SEARXNG_HOSTNAME; values withheld."
    }
    if ($port -notmatch '^[0-9]{1,5}$' -or [int]$port -lt 1 -or [int]$port -gt 65535) {
        throw "$Label has an invalid SEARXNG_PORT (expected 1-65535); values withheld."
    }
    [pscustomobject]@{ Secret = $secret; Hostname = $hostname; Port = [int]$port }
}

function Set-PrivateFileAccess {
    param([string]$Path)
    if ($IsWindows) {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [System.Security.AccessControl.FileSecurity]::new()
        $acl.SetOwner($sid)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
    else {
        $null = Invoke-DeployNative -FilePath 'chmod' -ArgumentList @('600', '--', $Path) `
            -TimeoutMilliseconds 10000 -Description 'Protect private environment file'
    }
}

function Assert-PrivateFileAccess {
    param($Context, [string]$Path)
    if ($Context.Mode -eq 'Local' -and $IsWindows) {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $acl = Get-Acl -LiteralPath $Path
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @($sid, 'S-1-5-18', 'S-1-5-32-544')) {
                throw 'Private .env grants access beyond the current user/system/administrators. Protect it with Initialize-Environment.ps1 or an equivalent private ACL.'
            }
        }
        return
    }
    $check = @'
set -eu
test ! -L "$1" && test -f "$1"
test "$(stat -c %u -- "$1")" = "$(id -u)"
case "$(stat -c %a -- "$1")" in 600|400) ;; *) exit 4 ;; esac
'@
    if ($Context.Mode -eq 'Local') {
        $null = Invoke-DeployNative -FilePath 'sh' -ArgumentList @('-c', $check, 'np-mcp', $Path) `
            -TimeoutMilliseconds 10000 -Description 'Validate private environment permissions (owner, mode 600/400)'
    }
    else {
        $null = Invoke-TargetShell -Context $Context -Script $check -ArgumentList @($Path) `
            -Description 'Validate private environment permissions (owner, mode 600/400)'
    }
}

function Write-PrivateEnvironment {
    param([string]$Path, [string]$Content)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $file = [System.IO.File]::Open($temporary, [System.IO.FileMode]::CreateNew)
        $file.Dispose()
        Set-PrivateFileAccess -Path $temporary
        [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Copy-DeploymentFile {
    param($Context, [string]$SourcePath, [string]$Destination, [string]$Description, [switch]$Private, [string]$Content)
    Write-Status '📤' $Description
    if ($Context.Mode -eq 'Local') {
        if ($Private) {
            if ($SourcePath) { $Content = [System.IO.File]::ReadAllText($SourcePath) }
            Write-PrivateEnvironment -Path $Destination -Content $Content
        }
        else { Copy-Item -LiteralPath $SourcePath -Destination $Destination -Force }
        return
    }
    $protect = if ($Private) { 'private' } else { 'public' }
    if ($Context.Mode -eq 'WSL' -and $SourcePath) {
        $copy = @'
set -eu
source=$(wslpath -u "$1")
test ! -L "$2"
if [ "$3" = private ]; then
  umask 077
  if [ -e "$2" ]; then chmod 600 -- "$2"; fi
fi
cp -- "$source" "$2"
if [ "$3" = private ]; then chmod 600 -- "$2"; fi
'@
        $null = Invoke-TargetShell -Context $Context -Script $copy -ArgumentList @($SourcePath, $Destination, $protect) -Description $Description
    }
    else {
        $copy = @'
set -eu
test ! -L "$1"
if [ "$2" = private ]; then
  umask 077
  if [ -e "$1" ]; then chmod 600 -- "$1"; fi
fi
cat > "$1"
if [ "$2" = private ]; then chmod 600 -- "$1"; fi
'@
        $bytes = if ($SourcePath) { [System.IO.File]::ReadAllBytes($SourcePath) } else { [System.Text.Encoding]::UTF8.GetBytes($Content) }
        $null = Invoke-TargetShell -Context $Context -Script $copy -ArgumentList @($Destination, $protect) -InputBytes $bytes -Description $Description
    }
}

function Invoke-DeploymentCompose {
    param($Context, [string[]]$ArgumentList, [string]$Description, [int]$TimeoutMilliseconds = $Context.CommandTimeoutMilliseconds)
    $composeArgs = @('compose', '--project-name', $Context.Project, '--project-directory', $Context.Path,
        '--env-file', $Context.EnvPath, '-f', $Context.ComposePath) + $ArgumentList
    if ($Context.Mode -eq 'Local') {
        Invoke-DeployNative -FilePath 'docker' -ArgumentList $composeArgs -WorkingDirectory $Context.Path `
            -RemoveEnvironment @('SEARXNG_SECRET', 'SEARXNG_HOSTNAME', 'SEARXNG_PORT', 'COMPOSE_FILE', 'COMPOSE_PROJECT_NAME', 'COMPOSE_ENV_FILES', 'COMPOSE_PROFILES') `
            -TimeoutMilliseconds $TimeoutMilliseconds -Description $Description
    }
    else {
        $compose = @'
set -eu
unset SEARXNG_SECRET SEARXNG_HOSTNAME SEARXNG_PORT COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_ENV_FILES COMPOSE_PROFILES
cd -- "$1"
shift
exec docker "$@"
'@
        Invoke-TargetShell -Context $Context -Script $compose -ArgumentList (@($Context.Path) + $composeArgs) `
            -TimeoutMilliseconds $TimeoutMilliseconds -Description $Description
    }
}

function Assert-DeploymentCompose {
    param($Context, $Environment)
    $output = Invoke-DeploymentCompose -Context $Context -ArgumentList @('config', '--format', 'json') -Description 'Validate deployed Compose configuration'
    try { $model = ConvertFrom-Json -InputObject $output -AsHashtable -ErrorAction Stop }
    catch { throw 'Compose configuration did not return valid JSON; output withheld to protect secrets.' }
    if ($model -isnot [System.Collections.IDictionary] -or $model['services'] -isnot [System.Collections.IDictionary] -or
        $model['services']['searxng'] -isnot [System.Collections.IDictionary]) {
        throw 'Deployed Compose configuration must define the searxng service.'
    }
    $service = $model['services']['searxng']
    $environmentMap = $service['environment']
    if ($environmentMap -isnot [System.Collections.IDictionary] -or
        -not (Test-DeploymentSecret ([string]$environmentMap['SEARXNG_SECRET'])) -or
        $environmentMap['SEARXNG_SECRET'] -cne $Environment.Secret) {
        throw 'Deployed Compose must explicitly map the validated SEARXNG_SECRET from its private .env. Republish the current Compose file; values withheld.'
    }
    if ($environmentMap.Contains('SEARXNG_PORT')) {
        throw 'Do not forward host SEARXNG_PORT into the container. The internal SearXNG port must remain 8080.'
    }
    if ($model['name'] -cne $Context.Project -or $service.Contains('container_name')) {
        throw 'Deployed Compose must use the requested isolated project and no global container_name. Plan legacy-stack migration separately.'
    }
    if ($model['networks'] -isnot [System.Collections.IDictionary]) { throw 'Deployed Compose must define project-scoped networks.' }
    foreach ($network in $model['networks'].Values) {
        if ($network -isnot [System.Collections.IDictionary] -or $network['external'] -or
            -not ([string]$network['name']).StartsWith($Context.Project + '_', [System.StringComparison]::Ordinal)) {
            throw 'Deployed Compose must use isolated, project-scoped networks, not global/external networks. Plan legacy-stack migration separately.'
        }
    }
}

function Wait-DeploymentReady {
    param($Context, [int]$TimeoutSeconds, [int]$PollSeconds)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -lt $TimeoutSeconds * 1000) {
        $remaining = $TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds
        $output = Invoke-DeploymentCompose -Context $Context -ArgumentList @('ps', '--all', '--format', 'json', 'searxng') `
            -Description 'Read SearXNG readiness' -TimeoutMilliseconds $remaining
        if ($clock.ElapsedMilliseconds -ge $TimeoutSeconds * 1000) { break }
        if ([string]::IsNullOrWhiteSpace($output)) { throw 'SearXNG is missing from Compose status.' }
        try {
            $rows = if ($output.TrimStart().StartsWith('[')) {
                @(ConvertFrom-Json -InputObject $output -ErrorAction Stop)
            }
            else {
                @($output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { ConvertFrom-Json -InputObject $_ -ErrorAction Stop })
            }
        }
        catch { throw 'Compose status is not valid JSON; readiness could not be established.' }
        $services = @($rows | Where-Object { $_ -and $_.PSObject.Properties['Service'] -and $_.Service -eq 'searxng' })
        if ($services.Count -ne 1) { throw 'Expected exactly one SearXNG service in Compose status; it is missing or ambiguous.' }
        $service = $services[0]
        if (-not $service.PSObject.Properties['State'] -or -not $service.PSObject.Properties['Health']) {
            throw 'SearXNG status lacks state/health evidence.'
        }
        if ($service.State -eq 'running' -and $service.Health -eq 'healthy') { return }
        if ($service.State -notin @('running', 'created') -or $service.Health -ne 'starting') {
            throw 'SearXNG is unhealthy, exited, stopped, or lacks a working healthcheck. Inspect the service privately; deployment is not ready.'
        }
        $remaining = $TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([Math]::Min($PollSeconds * 1000, $remaining)) }
    }
    throw "SearXNG readiness timed out after $TimeoutSeconds seconds."
}

function Initialize-McpEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$RotateSecret)
    $path = Join-Path $PSScriptRoot '.env'
    $file = Get-LocalDeploymentFile -Path $path -Label 'Source .env' -ReadContent
    $content = $file.Content
    if (-not $file.Exists) {
        $template = Get-LocalDeploymentFile -Path (Join-Path $PSScriptRoot '.env.example') -Label '.env.example' -ReadContent
        if (-not $template.Exists) { throw 'Required .env.example is missing; no private file was created.' }
        $content = $template.Content
    }
    $environment = Read-DeploymentEnvironment -Content $content -Label 'Source .env' -RequireSecret $false
    $valid = Test-DeploymentSecret $environment.Secret
    if ($environment.Secret -and -not $valid -and -not $RotateSecret) {
        throw 'Existing SEARXNG_SECRET is invalid. Use explicit -RotateSecret to replace it; values withheld.'
    }
    if (-not $PSCmdlet.ShouldProcess($path, 'Protect private .env; generate a key only if missing or rotation is explicit')) {
        Write-Status '⏭️' 'Preview/cancelled: no environment file or key was changed.'
        return
    }
    if ($valid -and -not $RotateSecret) {
        Set-PrivateFileAccess -Path $path
        Write-Status '🔒' 'Private .env protected; existing key and configuration preserved.'
        return
    }
    $bytes = [byte[]]::new(32)
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    $secret = [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
    $content = [regex]::Replace($content, '(?m)^\s*(?:export[ \t]+)?SEARXNG_SECRET[ \t]*=.*(?:\r?\n|$)', '')
    $content = $content.TrimEnd() + "`nSEARXNG_SECRET=$secret`n"
    Write-PrivateEnvironment -Path $path -Content $content
    Write-Status '🔒' 'Private .env written; key value withheld. Existing deployments are unchanged until explicitly deployed.'
}

function Invoke-McpDeployment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Remote', 'Local', 'WSL')][string]$DeployMode = 'Remote',
        [Alias('ComputerName', 'Host')][string]$TargetHost = 'raspberrypi',
        [string]$User = 'pi',
        [string]$RemotePath,
        [string]$WslDistro,
        [string]$ComposeFile = 'mcps.docker-compose.yml',
        [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$ProjectName = 'np-copilot-mcp',
        [switch]$SkipCopy,
        [switch]$Restart,
        [ValidateSet('Preserve', 'Require', 'Reset')][string]$EnvPolicy = 'Preserve',
        [switch]$RotateSecret,
        [ValidateRange(1, 3600)][int]$ReadinessTimeoutSeconds = 180,
        [ValidateRange(1, 30)][int]$ReadinessPollSeconds = 2,
        [ValidateRange(1, 3600)][int]$CommandTimeoutSeconds = 300
    )

    if (-not $RemotePath) { $RemotePath = if ($DeployMode -eq 'Local') { Join-Path $HOME 'DockerScripts' } else { '~/DockerScripts' } }
    if ($RemotePath -match '[\x00\r\n]' -or $ComposeFile -notmatch '^[^\\/\x00\r\n]+\.ya?ml$') {
        throw 'Use a single-line directory path and a Compose filename ending in .yml/.yaml (no directory components).'
    }
    if ($DeployMode -eq 'Local' -and $ComposeFile.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw 'Compose filename contains characters that are invalid on this filesystem.'
    }
    if ($DeployMode -ne 'Local' -and $RemotePath -notmatch '^(?:/|~(?:/|$))') { throw 'Remote/WSL paths must be absolute or start with ~/.' }
    if ($DeployMode -eq 'Remote' -and ($User -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*$' -or $TargetHost -notmatch '^[A-Za-z0-9_\[][A-Za-z0-9_.:\[\]-]*$')) {
        throw 'Invalid SSH user or host; use a hostname/IP, not command options.'
    }
    if ($SkipCopy -and ($EnvPolicy -ne 'Preserve' -or $RotateSecret)) { throw 'SkipCopy cannot copy/reset .env or authorize source-key rotation.' }
    if ($RotateSecret -and $EnvPolicy -eq 'Reset') { throw 'Reset preserves the deployed key; it cannot rotate it.' }

    $sourceCompose = Join-Path $PSScriptRoot 'docker-compose.yml'
    $sourceSettings = Join-Path $PSScriptRoot 'searxng\settings.yml'
    $sourceEnvPath = Join-Path $PSScriptRoot '.env'
    $sourceEnv = $null
    $sourceFile = $null
    $resetTemplate = $null
    if (-not $SkipCopy) {
        foreach ($required in @($sourceCompose, $sourceSettings)) {
            if (-not (Get-LocalDeploymentFile -Path $required -Label 'Required source input').Exists) {
                throw "Required source input is missing: $required. No target commands were run."
            }
        }
        $sourceFile = Get-LocalDeploymentFile -Path $sourceEnvPath -Label 'Source .env' -ReadContent
        if ($EnvPolicy -eq 'Reset') {
            $resetTemplate = Get-LocalDeploymentFile -Path (Join-Path $PSScriptRoot '.env.example') -Label 'Reset template' -ReadContent
            if (-not $resetTemplate.Exists) { throw 'Reset requires .env.example before target mutation.' }
            $null = Read-DeploymentEnvironment -Content $resetTemplate.Content -Label 'Reset template' -RequireSecret $false
        }
        elseif ($sourceFile.Exists) {
            $sourceEnv = Read-DeploymentEnvironment -Content $sourceFile.Content -Label 'Source .env'
            Assert-PrivateFileAccess -Context ([pscustomobject]@{ Mode = 'Local' }) -Path $sourceEnvPath
        }
        elseif ($EnvPolicy -eq 'Require' -or $RotateSecret) { throw 'This operation requires a valid source .env; initialize it privately first.' }
    }

    $target = switch ($DeployMode) {
        'Remote' { "${User}@${TargetHost}:$RemotePath" }
        'WSL' {
            $distroLabel = if ($WslDistro) { $WslDistro } else { 'default' }
            "WSL (${distroLabel}):$RemotePath"
        }
        'Local' { "localhost:$RemotePath" }
    }
    Write-Host "`nMCP deployment: $target; project $ProjectName; Compose $ComposeFile"
    Write-Status '⚠️' 'Legacy directory-derived stacks are not migrated or deleted. Confirm project/port ownership before the first deployment with this identity.'
    $action = if ($SkipCopy) { 'Validate deployed inputs, pull pinned image, reconcile SearXNG and wait for health' } else { 'Publish inputs, pull pinned image, recreate SearXNG and wait for health' }
    if ($Restart) { $action += ' (explicit recreation)' }
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        Write-Status '⏭️' "Preview/cancelled: no target commands or file writes. Env policy: $EnvPolicy; deployed inputs, effective key and readiness are unverified."
        return
    }

    $context = [pscustomobject]@{
        Mode = $DeployMode; SshTarget = "${User}@${TargetHost}"; Distro = $WslDistro
        Path = ''; Project = $ProjectName; ComposePath = ''; EnvPath = ''
        CommandTimeoutMilliseconds = $CommandTimeoutSeconds * 1000
    }
    $context.Path = Resolve-DeploymentPath -Context $context -Path $RemotePath
    $context.ComposePath = Join-DeploymentPath -Context $context -Child $ComposeFile
    $context.EnvPath = Join-DeploymentPath -Context $context -Child '.env'
    $settingsPath = Join-DeploymentPath -Context $context -Child 'searxng\settings.yml'
    $deployedCompose = Get-DeploymentFile -Context $context -Path $context.ComposePath -Label 'deployed Compose file'
    $deployedSettings = Get-DeploymentFile -Context $context -Path $settingsPath -Label 'deployed settings'
    $deployedFile = Get-DeploymentFile -Context $context -Path $context.EnvPath -Label 'deployed .env' -ReadContent
    if ($SkipCopy -and (-not $deployedCompose.Exists -or -not $deployedSettings.Exists -or -not $deployedFile.Exists)) {
        throw 'SkipCopy requires deployed Compose, searxng/settings.yml and a private .env; no files or containers were changed.'
    }
    $deployedEnv = $null
    if ($deployedFile.Exists) {
        $deployedEnv = Read-DeploymentEnvironment -Content $deployedFile.Content -Label 'Deployed .env' -RequireSecret (-not $RotateSecret)
    }
    if ($sourceEnv) {
        if ($deployedEnv -and $deployedEnv.Secret -cne $sourceEnv.Secret -and -not $RotateSecret) {
            throw 'Source and deployed keys differ. Reuse the deployed key or explicitly authorize -RotateSecret; values withheld.'
        }
        $environment = $sourceEnv
        Write-Status '🔒' 'Using validated source .env; existing keys may change only with explicit rotation.'
    }
    else {
        if (-not $deployedEnv) { throw 'No source .env or valid deployed .env is available. Initialize a private source .env; defaults cannot supply a key.' }
        $environment = $deployedEnv
        Assert-PrivateFileAccess -Context $context -Path $context.EnvPath
        if ($EnvPolicy -eq 'Reset') {
            $resetContent = [regex]::Replace($resetTemplate.Content, '(?m)^\s*(?:export[ \t]+)?SEARXNG_SECRET[ \t]*=.*(?:\r?\n|$)', '')
            $resetContent = $resetContent.TrimEnd() + "`nSEARXNG_SECRET=$($deployedEnv.Secret)`n"
            $environment = Read-DeploymentEnvironment -Content $resetContent -Label 'Reset environment'
            Write-Status '🔒' 'Explicit reset: using example nonsecret defaults; deployed key retained.'
        }
        else { Write-Status '🔒' 'Preserving deployed .env, including its custom settings and key; not assuming defaults.' }
    }

    if (-not $SkipCopy) {
        $directory = Join-DeploymentPath -Context $context -Child 'searxng'
        Write-Status '🔧' 'Prepare target directory'
        if ($DeployMode -eq 'Local') { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        else {
            $null = Invoke-TargetShell -Context $context -Script 'set -eu; mkdir -p -- "$1"' -ArgumentList @($directory) -Description 'Prepare target directory'
        }
        Copy-DeploymentFile -Context $context -SourcePath $sourceCompose -Destination $context.ComposePath -Description 'Publish Compose file'
        Copy-DeploymentFile -Context $context -SourcePath $sourceSettings -Destination $settingsPath -Description 'Publish SearXNG settings'
        if ($sourceEnv) { Copy-DeploymentFile -Context $context -SourcePath $sourceEnvPath -Destination $context.EnvPath -Description 'Publish private .env' -Private }
        elseif ($EnvPolicy -eq 'Reset') { Copy-DeploymentFile -Context $context -Destination $context.EnvPath -Content $resetContent -Description 'Reset private .env' -Private }
    }
    Assert-PrivateFileAccess -Context $context -Path $context.EnvPath
    Assert-DeploymentCompose -Context $context -Environment $environment
    Write-Status '🔧' 'Pull pinned SearXNG image'
    $null = Invoke-DeploymentCompose -Context $context -ArgumentList @('pull', 'searxng') -Description 'Pull pinned SearXNG image'
    $upArgs = @('up', '-d', '--no-deps')
    if (-not $SkipCopy -or $Restart) { $upArgs += '--force-recreate' }
    $upArgs += 'searxng'
    $null = Invoke-DeploymentCompose -Context $context -ArgumentList $upArgs -Description 'Start SearXNG'
    Write-Status '🔧' "Wait up to $ReadinessTimeoutSeconds seconds for SearXNG health"
    Wait-DeploymentReady -Context $context -TimeoutSeconds $ReadinessTimeoutSeconds -PollSeconds $ReadinessPollSeconds
    Write-Status '✅' 'MCP stack is ready (SearXNG healthy). Functional search was not tested.'
}

Export-ModuleMember -Function Invoke-McpDeployment, Initialize-McpEnvironment
