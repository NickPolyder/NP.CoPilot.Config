#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Read-RepositoryYamlScalar {
    param([AllowEmptyString()][string]$Text, [string]$Location)

    $value = $Text.Trim()
    if ($value.StartsWith('"')) {
        if ($value -notmatch '\A(?<quoted>"(?:[^"\\]|\\.)*")\s*(?:#.*)?\z') {
            throw "${Location}: malformed double-quoted scalar."
        }
        try { return [pscustomobject]@{ Value = ($Matches.quoted | ConvertFrom-Json -ErrorAction Stop) } }
        catch { throw "${Location}: invalid JSON-compatible quoted string: $($_.Exception.Message)" }
    }
    if ($value.StartsWith("'")) {
        if ($value -notmatch "\A'(?<quoted>(?:[^']|'')*)'\s*(?:#.*)?\z") {
            throw "${Location}: malformed single-quoted scalar."
        }
        return [pscustomobject]@{ Value = $Matches.quoted.Replace("''", "'") }
    }
    if ($value.StartsWith('[')) {
        $items = [Collections.Generic.List[object]]::new()
        $token = [Text.StringBuilder]::new()
        $quote = [char]0
        $closed = $false
        for ($i = 1; $i -lt $value.Length; $i++) {
            $character = $value[$i]
            if ($quote -ne [char]0) {
                $null = $token.Append($character)
                if ($quote -eq '"' -and $character -eq '\') {
                    if (++$i -ge $value.Length) { throw "${Location}: unterminated flow-sequence escape." }
                    $null = $token.Append($value[$i])
                }
                elseif ($character -eq $quote) {
                    if ($quote -eq "'" -and $i + 1 -lt $value.Length -and $value[$i + 1] -eq "'") {
                        $null = $token.Append($value[++$i])
                    }
                    else { $quote = [char]0 }
                }
                continue
            }
            if ($character -in @("'", '"') -and [string]::IsNullOrWhiteSpace($token.ToString())) {
                $quote = $character
                $null = $token.Append($character)
            }
            elseif ($character -in @(',', ']')) {
                if ([string]::IsNullOrWhiteSpace($token.ToString())) {
                    if ($character -eq ',' -or $items.Count -gt 0) { throw "${Location}: empty flow-sequence item or trailing comma." }
                }
                else {
                    $item = Read-RepositoryYamlScalar -Text $token.ToString() -Location $Location
                    if ($item.Value -is [array]) { throw "${Location}: nested flow sequences are unsupported." }
                    $items.Add($item.Value)
                }
                $null = $token.Clear()
                if ($character -eq ']') {
                    if ($value.Substring($i + 1) -notmatch '^\s*(?:#.*)?$') { throw "${Location}: unexpected text after flow sequence." }
                    $closed = $true
                    break
                }
            }
            elseif ($character -in @('[', '{', '}')) {
                throw "${Location}: nested flow collections are unsupported."
            }
            elseif ($character -eq '#') {
                throw "${Location}: comments inside flow sequences are unsupported; quote literal hash characters."
            }
            else { $null = $token.Append($character) }
        }
        if (-not $closed -or $quote -ne [char]0) { throw "${Location}: unterminated flow sequence." }
        return [pscustomobject]@{ Value = $items.ToArray() }
    }

    $value = ($value -replace '\s+#.*$', '').Trim()
    if (-not $value -or $value.StartsWith('#') -or $value -match '^(?:null|~)$') {
        return [pscustomobject]@{ Value = $null }
    }
    if ($value -match '^[\[\]{}&*!|>@`"%''?,]|^[-:](?:\s|$)|:(?:\s|$)') {
        throw "${Location}: unsupported or ambiguous plain scalar; quote it or use the documented subset."
    }
    if ($value -match '^(?:yes|no|on|off|\.nan|[-+]?\.inf)$|^\d{4}-\d{2}-\d{2}(?:[Tt ]|$)|^[-+]?0(?:[0-9]+|[xob][0-9a-f]+)$') {
        throw "${Location}: ambiguous plain scalar '$value'; use an explicit quoted string."
    }
    if ($value -match '^(?:true|false)$') { return [pscustomobject]@{ Value = ($value -ieq 'true') } }
    if ($value -match '^[-+]?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?$') {
        $number = [double]::Parse($value, [Globalization.CultureInfo]::InvariantCulture)
        return [pscustomobject]@{ Value = $number }
    }
    [pscustomobject]@{ Value = $value }
}

function Move-RepositoryYamlCursor {
    param($State)

    while ($State.Index -lt $State.Lines.Length -and $State.Lines[$State.Index] -match '^\s*(?:#.*)?$') {
        $State.Index++
    }
}

function Read-RepositoryYamlBlock {
    param($State, [int]$Indent)

    Move-RepositoryYamlCursor $State
    $sequence = $State.Lines[$State.Index].TrimStart().StartsWith('- ')
    $mapping = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $items = [Collections.Generic.List[object]]::new()
    while ($State.Index -lt $State.Lines.Length) {
        Move-RepositoryYamlCursor $State
        if ($State.Index -ge $State.Lines.Length) { break }
        $line = $State.Lines[$State.Index]
        $actualIndent = $line.Length - $line.TrimStart(' ').Length
        $location = "$($State.Source):$($State.Index + 1)"
        if ($actualIndent -lt $Indent) { break }
        if ($actualIndent -ne $Indent) { throw "${location}: indentation must increase by exactly two spaces." }
        $text = $line.Substring($Indent)
        $State.Index++
        if ($sequence) {
            if (-not $text.StartsWith('- ')) { throw "${location}: mixed mapping and sequence entries are unsupported." }
            $item = Read-RepositoryYamlScalar -Text $text.Substring(2) -Location $location
            if ($null -eq $item.Value -or $item.Value -is [array]) { throw "${location}: block sequences require scalar items." }
            $items.Add($item.Value)
            continue
        }
        if ($text -notmatch '\A(?<key>[A-Za-z_][A-Za-z0-9_.-]*|"(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*''):(?<tail>(?:[ ].*)?)\z') {
            throw "${location}: malformed or unsupported mapping entry."
        }
        $keyText = $Matches.key
        $tail = $Matches.tail.TrimStart()
        $key = (Read-RepositoryYamlScalar -Text $keyText -Location $location).Value
        if ($key -isnot [string] -or -not $key) { throw "${location}: mapping keys must be nonempty strings." }
        if ($mapping.ContainsKey($key)) { throw "${location}: duplicate YAML key '$key'." }
        $fieldLocation = "$location ($key)"
        if ($tail -match '^(?<style>[>|])(?<chomp>-)?\s*(?:#.*)?$') {
            $style = $Matches.style
            $strip = $Matches.chomp -eq '-'
            $block = [Collections.Generic.List[string]]::new()
            while ($State.Index -lt $State.Lines.Length) {
                $blockLine = $State.Lines[$State.Index]
                if ([string]::IsNullOrWhiteSpace($blockLine)) {
                    $block.Add('')
                    $State.Index++
                    continue
                }
                $blockIndent = $blockLine.Length - $blockLine.TrimStart(' ').Length
                if ($blockIndent -le $Indent) { break }
                if ($blockIndent -ne $Indent + 2) { throw "${fieldLocation}: block strings require exactly two additional spaces." }
                $block.Add($blockLine.Substring($Indent + 2))
                $State.Index++
            }
            $blockValue = $block -join "`n"
            if ($style -eq '>') { $blockValue = $blockValue -replace '(?<=\S)\n(?=\S)', ' ' }
            $blockValue = $blockValue.TrimEnd("`n")
            if (-not $strip) { $blockValue += "`n" }
            $mapping.Add($key, $blockValue)
        }
        elseif (-not $tail -or $tail.StartsWith('#')) {
            Move-RepositoryYamlCursor $State
            $child = $null
            if ($State.Index -lt $State.Lines.Length) {
                $nextLine = $State.Lines[$State.Index]
                $nextIndent = $nextLine.Length - $nextLine.TrimStart(' ').Length
                if ($nextIndent -gt $Indent) {
                    if ($nextIndent -ne $Indent + 2) { throw "${fieldLocation}: indentation must increase by exactly two spaces." }
                    $child = (Read-RepositoryYamlBlock -State $State -Indent ($Indent + 2)).Value
                }
            }
            $mapping.Add($key, $child)
        }
        else {
            $mapping.Add($key, (Read-RepositoryYamlScalar -Text $tail -Location $fieldLocation).Value)
        }
    }
    [pscustomobject]@{ Value = $(if ($sequence) { ,$items.ToArray() } else { $mapping }) }
}

function ConvertFrom-RepositoryYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$SourceName
    )

    if ($Text.Contains("`t") -or ($Text -replace "`r`n", "`n").Contains("`r")) {
        throw "${SourceName}: tabs and bare carriage returns are unsupported YAML syntax."
    }
    if ($Text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u2028\u2029]') {
        throw "${SourceName}: control characters and non-LF line separators are unsupported YAML syntax."
    }
    $state = [pscustomobject]@{ Lines = ($Text -split '\r?\n'); Index = 0; Source = $SourceName }
    Move-RepositoryYamlCursor $state
    if ($state.Index -ge $state.Lines.Length) { throw "${SourceName}: expected one nonempty YAML mapping." }
    $node = Read-RepositoryYamlBlock -State $state -Indent 0
    if ($node.Value -isnot [Collections.IDictionary] -or $state.Index -lt $state.Lines.Length) {
        throw "${SourceName}: expected exactly one complete YAML mapping."
    }
    $node.Value
}

Export-ModuleMember -Function ConvertFrom-RepositoryYaml
