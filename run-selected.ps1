[CmdletBinding()]
param()

$selectionFile = Join-Path $PSScriptRoot "scripts-to-run.ps1"
$scriptsRoot = Join-Path $PSScriptRoot "scripts"

function New-SelectionFile {
    param(
        [string]$Path,
        [string]$ScriptsRoot
    )

    if (-not (Test-Path $ScriptsRoot)) {
        Write-Warning "Scripts folder not found: $ScriptsRoot"
        return
    }

    $scriptFiles = Get-ChildItem -Path $ScriptsRoot -Filter *.ps1 | Sort-Object Name
    $lines = @(
        "# Comment out any script lines you do not want to run.",
        "# Save and close the editor to continue.",
        ""
    )

    foreach ($file in $scriptFiles) {
        $lines += ". `"$PSScriptRoot\scripts\$($file.Name)`""
    }

    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

if (-not (Test-Path $selectionFile)) {
    New-SelectionFile -Path $selectionFile -ScriptsRoot $scriptsRoot
}

if (-not (Test-Path $selectionFile)) {
    Write-Warning "Selection file not found: $selectionFile"
    exit 1
}

Write-Host "Opening $selectionFile. Comment out any scripts you do not want to run."
Start-Process -FilePath $selectionFile -Wait

Write-Host "Running selected scripts..."
. $selectionFile
