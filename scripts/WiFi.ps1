<#
.SYNOPSIS
Applies the Wi-Fi profile order kept in Infisical: creates missing profiles, sets priorities,
marks the phone hotspot as auto-switching and metered, and deletes retired profiles.

.DESCRIPTION
Runs unelevated and is idempotent. Reads WIFI_ORDER and one password secret per network from
Infisical (env prod, folder /workstation/wifi). See config/wifi-order.example.json and the README.
If anything it needs is missing or unreachable, it warns and changes nothing.

.EXAMPLE
.\scripts\WiFi.ps1 -WhatIf
Shows what would change, without touching profiles, certificates or environment variables.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

# Dot-sourced by run-selected.ps1, so never `exit`: that would end the whole runner.
Import-Module (Join-Path $PSScriptRoot 'lib\WiFi.psm1') -Force
try {
    Invoke-WifiSync -WhatIf:$WhatIfPreference -Verbose:($VerbosePreference -eq 'Continue')
} catch {
    Write-Warning "WiFi: $($_.Exception.Message) Nothing more applied."
}
