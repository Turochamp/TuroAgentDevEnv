# Bootstrap script for a fresh Windows machine.
# Installs core tools (winget/choco/git), clones the repo, and starts the runner.

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/Turochamp/TuroAgentDevEnv.git",
    [string]$InstallDir = (Join-Path $env:USERPROFILE "dotfiles")
)

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-Winget {
    if (Test-Command "winget") {
        return $true
    }
    Write-Warning "winget not found. Install 'App Installer' from Microsoft Store, then re-run."
    return $false
}

function Ensure-Chocolatey {
    if (Test-Command "choco") {
        return $true
    }

    Write-Host "Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
        return $true
    } catch {
        Write-Warning "Chocolatey install failed: $($_.Exception.Message)"
        return $false
    }
}

function Ensure-Git {
    if (Test-Command "git") {
        return
    }

    if ($script:HasWinget) {
        winget install -e -h --id Git.Git
    } elseif ($script:HasChoco) {
        choco install -y git
    } else {
        Write-Warning "Git not found and no installer available."
    }
}

$script:HasWinget = Ensure-Winget
$script:HasChoco = Ensure-Chocolatey

Ensure-Git
if (-not (Test-Command "git")) {
    Write-Warning "Git is still not available. Exiting."
    exit 1
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

if (-not (Test-Path (Join-Path $InstallDir ".git"))) {
    git clone $RepoUrl $InstallDir
} else {
    Write-Host "Repo already exists at $InstallDir; skipping clone."
}

$runner = Join-Path $InstallDir "run-selected.ps1"
if (Test-Path $runner) {
    & $runner
} else {
    Write-Warning "Runner not found: $runner"
}
