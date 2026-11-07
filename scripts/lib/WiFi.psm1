Set-StrictMode -Version 3.0

function ConvertFrom-WifiOrder {
    <#
    .SYNOPSIS
    Parses and validates the WIFI_ORDER JSON array. Throws on anything malformed.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Json)

    try {
        $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    } catch {
        throw "WIFI_ORDER is not valid JSON: $($_.Exception.Message)"
    }
    # PS 5.1 returns an array as one object and PS 7 unrolls a one-element array, so check the text.
    if (-not $Json.TrimStart().StartsWith('[')) {
        throw 'WIFI_ORDER must be a JSON array of {"ssid":...} entries.'
    }

    $seen = @{}
    $hotspots = 0
    $entries = foreach ($item in @($parsed)) {
        $names = @($item.PSObject.Properties.Name)
        $ssid = if ($names -contains 'ssid') { [string]$item.ssid } else { '' }
        $secret = if ($names -contains 'secret') { [string]$item.secret } else { $null }
        $hotspot = ($names -contains 'hotspot') -and [bool]$item.hotspot
        $retired = ($names -contains 'retired') -and [bool]$item.retired

        if ([string]::IsNullOrWhiteSpace($ssid)) {
            throw 'WIFI_ORDER has an entry without an ssid.'
        }
        if ($seen.ContainsKey($ssid)) {
            throw "WIFI_ORDER lists '$ssid' more than once."
        }
        $seen[$ssid] = $true
        if ($retired -and $hotspot) {
            throw "WIFI_ORDER entry '$ssid' is both retired and the hotspot."
        }
        if (-not $retired) {
            if ([string]::IsNullOrEmpty($secret)) {
                throw "WIFI_ORDER entry '$ssid' needs a secret name, or retired:true."
            }
            if ($secret -cnotmatch '^[A-Z0-9_]+$') {
                throw "WIFI_ORDER entry '$ssid': secret name '$secret' must be upper-snake (A-Z, 0-9, _)."
            }
        }
        if ($hotspot) { $hotspots++ }

        [pscustomobject]@{
            Ssid    = $ssid
            Secret  = $secret
            Hotspot = $hotspot
            Retired = $retired
        }
    }
    if ($hotspots -gt 1) {
        throw 'WIFI_ORDER may mark only one hotspot.'
    }
    return , @($entries)
}

function New-WlanProfileXml {
    <#
    .SYNOPSIS
    Pure: builds a WPA2-Personal (AES) WLAN profile. WPA2/WPA3 transition networks accept it too.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure; returns a string.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'A WLAN profile holds the PSK as plain text by design.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Ssid,
        [Parameter(Mandatory)][string]$Password
    )

    $hex = -join ([Text.Encoding]::UTF8.GetBytes($Ssid) | ForEach-Object { $_.ToString('X2') })
    $name = [Security.SecurityElement]::Escape($Ssid)
    $key = [Security.SecurityElement]::Escape($Password)

    return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$name</name>
    <SSIDConfig>
        <SSID>
            <hex>$hex</hex>
            <name>$name</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$key</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
}

function New-WifiAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure; returns an object.')]
    param([string]$Action, [string]$Ssid, [int]$Priority = 0, [string]$Secret = $null, [string]$Message = $null)
    [pscustomobject]@{ Action = $Action; Ssid = $Ssid; Priority = $Priority; Secret = $Secret; Message = $Message }
}

function Get-WifiPlan {
    <#
    .SYNOPSIS
    Pure: turns the wanted order, the profiles present (in priority order) and the secrets into an
    ordered list of actions. Actions carry secret names, never passwords.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Order,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Existing,
        [Parameter(Mandatory)][hashtable]$Secrets
    )

    $present = @{}
    foreach ($name in $Existing) { $present[$name] = $true }

    $deletes = @()
    $creates = @()
    $warns = @()
    $managed = @()
    $hotspot = $null

    foreach ($entry in $Order) {
        if ($entry.Retired) {
            if ($present.ContainsKey($entry.Ssid)) {
                $deletes += New-WifiAction -Action 'Delete' -Ssid $entry.Ssid
            }
            continue
        }
        if (-not $present.ContainsKey($entry.Ssid)) {
            $known = $Secrets.ContainsKey($entry.Secret) -and -not [string]::IsNullOrEmpty($Secrets[$entry.Secret])
            if (-not $known) {
                $warns += New-WifiAction -Action 'Warn' -Ssid $entry.Ssid -Message "Profile '$($entry.Ssid)' is missing and secret $($entry.Secret) has no value; skipped."
                continue
            }
            $creates += New-WifiAction -Action 'Create' -Ssid $entry.Ssid -Secret $entry.Secret
        }
        $managed += $entry.Ssid
        if ($entry.Hotspot) { $hotspot = $entry.Ssid }
    }

    # Skip the reorder only when nothing is created and the managed profiles already sit on top, in order.
    $priorities = @()
    $deleted = @($deletes | ForEach-Object { $_.Ssid })
    $remaining = @($Existing | Where-Object { $deleted -notcontains $_ })
    $inOrder = $creates.Count -eq 0 -and $remaining.Count -ge $managed.Count
    for ($i = 0; $inOrder -and $i -lt $managed.Count; $i++) {
        if ($remaining[$i] -ne $managed[$i]) { $inOrder = $false }
    }
    if (-not $inOrder) {
        for ($i = 0; $i -lt $managed.Count; $i++) {
            $priorities += New-WifiAction -Action 'SetPriority' -Ssid $managed[$i] -Priority ($i + 1)
        }
    }

    $plan = @($warns) + @($deletes) + @($creates) + @($priorities)
    if ($hotspot) {
        $plan += New-WifiAction -Action 'SetHotspot' -Ssid $hotspot
    }
    return , @($plan)
}

$script:NetshField = '^\s+[^:]+?\s+:\s(.*?)\s*$'

function ConvertFrom-NetshProfileList {
    <#
    .SYNOPSIS
    Pure: user profile names from `netsh wlan show profiles`, in priority order. Labels are
    localised, so it keys on layout: the entries under the last dashed rule.
    #>
    [CmdletBinding()]
    [OutputType([string], [object[]])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $lines = $Text -split '\r?\n'
    $lastRule = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*-{3,}\s*$') { $lastRule = $i }
    }
    $names = @()
    if ($lastRule -ge 0) {
        for ($i = $lastRule + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $script:NetshField) { $names += $Matches[1] }
        }
    }
    return $names
}

function ConvertFrom-NetshInterfaceList {
    <#
    .SYNOPSIS
    Pure: interface names from `netsh wlan show interfaces`. The first field of each block is the
    name, whatever the label is in this locale.
    #>
    [CmdletBinding()]
    [OutputType([string], [object[]])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $names = @()
    $inBlock = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match $script:NetshField) {
            if (-not $inBlock) { $names += $Matches[1] }
            $inBlock = $true
        } else {
            $inBlock = $false
        }
    }
    return $names
}


function ConvertFrom-InfisicalExport {
    <#
    .SYNOPSIS
    Pure: `infisical export --format json` output (an array of {key, value, ...}) to a hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $secrets = @{}
    if ([string]::IsNullOrWhiteSpace($Json)) { return $secrets }
    $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    foreach ($item in @($parsed)) {
        if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'key') {
            $secrets[[string]$item.key] = [string]$item.value
        }
    }
    return $secrets
}

# ---------------------------------------------------------------------------------------------
# Thin wrappers over the outside world. Tests mock these; nothing below them is unit-tested.
# ---------------------------------------------------------------------------------------------

function Invoke-NativeCommand {
    param([string]$FilePath, [string[]]$ArgumentList, [switch]$Utf8)

    $ErrorActionPreference = 'Continue'
    $previous = $null
    if ($Utf8) {
        try {
            $previous = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        } catch { $previous = $null }
    }
    try {
        $all = & $FilePath @ArgumentList 2>&1
        $code = $LASTEXITCODE
    } catch {
        return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = $_.Exception.Message }
    } finally {
        if ($previous) { [Console]::OutputEncoding = $previous }
    }
    [pscustomobject]@{
        ExitCode = $code
        Output   = @($all | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "`n"
        Error    = @($all | Where-Object { $_ -is [Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"
    }
}

function Invoke-Netsh {
    param([string[]]$ArgumentList)
    Invoke-NativeCommand -FilePath 'netsh.exe' -ArgumentList $ArgumentList
}

function Invoke-Gh {
    param([string[]]$ArgumentList)
    Invoke-NativeCommand -FilePath 'gh' -ArgumentList $ArgumentList -Utf8
}

function Invoke-Infisical {
    param([string[]]$ArgumentList)
    Invoke-NativeCommand -FilePath 'infisical' -ArgumentList $ArgumentList -Utf8
}

function Invoke-InfisicalLogin {
    # Interactive: output goes straight to the console. Returns the exit code.
    param([string]$Domain)
    & infisical login --domain $Domain
    return $LASTEXITCODE
}

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-InfisicalCli {
    if (Test-CommandAvailable 'winget') {
        winget install -e -h --id infisical.infisical --accept-package-agreements --accept-source-agreements
    } elseif (Test-CommandAvailable 'choco') {
        choco install -y infisical
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Get-UserEnvironmentValue {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrEmpty($value)) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
    return $value
}

function Set-UserEnvironmentValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Caller decides via ShouldProcess.')]
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Read-ConfigValue {
    param([string]$Prompt)
    return Read-Host -Prompt $Prompt
}

function Test-TrustedRoot {
    param([string]$Thumbprint)
    return Test-Path -LiteralPath "Cert:\CurrentUser\Root\$Thumbprint"
}

function Add-TrustedRoot {
    # CurrentUser needs no admin; Windows shows a one-time confirmation dialog.
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $store = New-Object Security.Cryptography.X509Certificates.X509Store 'Root', 'CurrentUser'
    $store.Open('ReadWrite')
    try { $store.Add($Certificate) } finally { $store.Close() }
}

# ---------------------------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------------------------

$script:ConfigPrompts = [ordered]@{
    WORKSTATION_INFISICAL_URL        = 'Infisical URL, e.g. https://infisical.example.lan:8443'
    WORKSTATION_INFISICAL_PROJECT_ID = 'Infisical project ID'
    WORKSTATION_CA_SOURCE            = "Root CA as a gh contents path, owner/repo/path/to/root.crt ('none' to skip)"
}

function Get-WifiSyncConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param()

    $config = @{}
    foreach ($name in $script:ConfigPrompts.Keys) {
        $value = Get-UserEnvironmentValue -Name $name
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = Read-ConfigValue -Prompt $script:ConfigPrompts[$name]
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Warning "WiFi: $name not set; nothing applied."
                return $null
            }
            $value = $value.Trim()
            if ($PSCmdlet.ShouldProcess("user environment variable $name", 'Store')) {
                Set-UserEnvironmentValue -Name $name -Value $value
            }
        }
        $config[$name] = $value
    }
    return $config
}

function Confirm-RootCaTrusted {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([string]$Source)

    if ($Source -notmatch '^([^/]+)/([^/]+)/(.+)$') {
        Write-Warning "WiFi: CA source '$Source' is not owner/repo/path; nothing applied."
        return $false
    }
    $fetched = Invoke-Gh -ArgumentList @('api', "repos/$($Matches[1])/$($Matches[2])/contents/$($Matches[3])", '--jq', '.content')
    if ($fetched.ExitCode -ne 0) {
        Write-Warning "WiFi: could not fetch CA $Source with gh; nothing applied."
        return $false
    }
    try {
        $bytes = [Convert]::FromBase64String(($fetched.Output -replace '\s', ''))
        $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (, $bytes)
    } catch {
        Write-Warning "WiFi: $Source is not a certificate; nothing applied."
        return $false
    }
    if (Test-TrustedRoot -Thumbprint $cert.Thumbprint) {
        Write-Verbose "WiFi: CA $($cert.Subject) already trusted."
        return $true
    }
    if ($PSCmdlet.ShouldProcess('Cert:\CurrentUser\Root', "Add $($cert.Subject) ($($cert.Thumbprint))")) {
        try {
            Add-TrustedRoot -Certificate $cert
        } catch {
            Write-Warning "WiFi: CA not added ($($_.Exception.Message)); nothing applied."
            return $false
        }
    }
    return $true
}

function Get-WifiSecret {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script; progress goes to the console, like bootstrap.ps1.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$Url, [string]$ProjectId)

    if (-not (Test-CommandAvailable 'infisical')) {
        Write-Host 'WiFi: installing the Infisical CLI.'
        Install-InfisicalCli
        if (-not (Test-CommandAvailable 'infisical')) {
            Write-Warning 'WiFi: Infisical CLI not installed; nothing applied.'
            return $null
        }
    }

    $status = Invoke-Infisical -ArgumentList @('login', 'status', '--domain', $Url, '--silent')
    if ($status.ExitCode -ne 0) {
        Write-Host "WiFi: not logged in to $Url; starting infisical login."
        if ((Invoke-InfisicalLogin -Domain $Url) -ne 0) {
            Write-Warning 'WiFi: Infisical login failed or cancelled; nothing applied.'
            return $null
        }
    }

    $export = Invoke-Infisical -ArgumentList @(
        'export', '--projectId', $ProjectId, '--env', 'prod', '--path', '/workstation/wifi',
        '--format', 'json', '--domain', $Url, '--silent')
    if ($export.ExitCode -ne 0) {
        Write-Warning "WiFi: Infisical export failed ($([string]$export.Error)); nothing applied."
        return $null
    }
    try {
        return ConvertFrom-InfisicalExport -Json $export.Output
    } catch {
        Write-Warning 'WiFi: Infisical export is not JSON; nothing applied.'
        return $null
    }
}

function Invoke-WifiAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script; progress goes to the console, like bootstrap.ps1.')]
    [CmdletBinding(SupportsShouldProcess)]
    param([object]$Action, [string]$Interface, [hashtable]$Secrets)

    $ssid = $Action.Ssid
    if ($Action.Action -eq 'Warn') {
        Write-Warning "WiFi: $($Action.Message)"
        return
    }
    if ($Action.Action -eq 'Create') {
        if (-not $PSCmdlet.ShouldProcess($ssid, 'Create profile')) { return }
        $file = Join-Path ([IO.Path]::GetTempPath()) ("wifi-$([guid]::NewGuid()).xml")
        try {
            $xml = New-WlanProfileXml -Ssid $ssid -Password $Secrets[$Action.Secret]
            [IO.File]::WriteAllText($file, $xml, (New-Object Text.UTF8Encoding $false))
            $result = Invoke-Netsh -ArgumentList @('wlan', 'add', 'profile', "filename=$file", "interface=$Interface", 'user=current')
        } finally {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    } elseif ($Action.Action -eq 'SetPriority') {
        if (-not $PSCmdlet.ShouldProcess($ssid, "Set priority $($Action.Priority)")) { return }
        $result = Invoke-Netsh -ArgumentList @('wlan', 'set', 'profileorder', "name=$ssid", "interface=$Interface", "priority=$($Action.Priority)")
    } elseif ($Action.Action -eq 'SetHotspot') {
        if (-not $PSCmdlet.ShouldProcess($ssid, 'Set hotspot: connect automatically, AutoSwitch, metered')) { return }
        $result = Invoke-Netsh -ArgumentList @('wlan', 'set', 'profileparameter', "name=$ssid", "interface=$Interface", 'connectionmode=auto', 'autoSwitch=yes', 'cost=Fixed')
    } elseif ($Action.Action -eq 'Delete') {
        if (-not $PSCmdlet.ShouldProcess($ssid, 'Delete retired profile')) { return }
        $result = Invoke-Netsh -ArgumentList @('wlan', 'delete', 'profile', "name=$ssid", "interface=$Interface")
    } else {
        Write-Warning "WiFi: unknown action $($Action.Action)."
        return
    }

    if ($result.ExitCode -ne 0) {
        Write-Warning "WiFi: $($Action.Action) '$ssid' failed: $([string]$result.Output) $([string]$result.Error)"
    } else {
        Write-Host "WiFi: $($Action.Action) '$ssid'."
    }
}

function Invoke-WifiSync {
    <#
    .SYNOPSIS
    Applies WIFI_ORDER from Infisical to this machine's Wi-Fi profiles. Idempotent; no admin.
    Any missing prerequisite warns and returns without changes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup script; progress goes to the console, like bootstrap.ps1.')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $config = Get-WifiSyncConfig
    if (-not $config) { return }
    $url = $config.WORKSTATION_INFISICAL_URL

    if ($config.WORKSTATION_CA_SOURCE -ne 'none') {
        if (-not (Test-CommandAvailable 'gh')) {
            Write-Warning 'WiFi: gh not installed; nothing applied.'
            return
        }
        if ((Invoke-Gh -ArgumentList @('auth', 'status')).ExitCode -ne 0) {
            Write-Warning "WiFi: gh not logged in; run 'gh auth login'. Nothing applied."
            return
        }
        if (-not (Confirm-RootCaTrusted -Source $config.WORKSTATION_CA_SOURCE)) { return }
    }

    $secrets = Get-WifiSecret -Url $url -ProjectId $config.WORKSTATION_INFISICAL_PROJECT_ID
    if ($null -eq $secrets) { return }
    if (-not $secrets.ContainsKey('WIFI_ORDER')) {
        Write-Warning 'WiFi: WIFI_ORDER not found in /workstation/wifi; nothing applied.'
        return
    }
    try {
        $order = ConvertFrom-WifiOrder -Json $secrets['WIFI_ORDER']
    } catch {
        Write-Warning "WiFi: $($_.Exception.Message) Nothing applied."
        return
    }

    $interfaces = @(ConvertFrom-NetshInterfaceList -Text (Invoke-Netsh -ArgumentList @('wlan', 'show', 'interfaces')).Output)
    if ($interfaces.Count -eq 0) {
        Write-Warning 'WiFi: no Wi-Fi interface found; nothing applied.'
        return
    }
    $interface = $interfaces[0]
    if ($interfaces.Count -gt 1) { Write-Warning "WiFi: $($interfaces.Count) interfaces; using '$interface'." }

    $existing = @(ConvertFrom-NetshProfileList -Text (Invoke-Netsh -ArgumentList @('wlan', 'show', 'profiles', "interface=$interface")).Output)
    $plan = Get-WifiPlan -Order $order -Existing $existing -Secrets $secrets
    if ($plan.Count -eq 0) {
        Write-Host 'WiFi: already in the target state.'
        return
    }
    foreach ($action in $plan) {
        Invoke-WifiAction -Action $action -Interface $interface -Secrets $secrets
    }
}

Export-ModuleMember -Function ConvertFrom-WifiOrder, New-WlanProfileXml, Get-WifiPlan,
ConvertFrom-NetshProfileList, ConvertFrom-NetshInterfaceList, ConvertFrom-InfisicalExport, Invoke-WifiSync
