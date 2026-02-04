# ---------------------------------------------- #
# Browsers  ------------------------------------ #
# ---------------------------------------------- #
choco install -y googlechrome
#choco install -y firefox

# ---------------------------------------------- #
# Common tools  --------------------------------- #
# ---------------------------------------------- #
winget install -e -h --id 7zip.7zip --accept-package-agreements --accept-source-agreements
winget install -e -h --id dotPDNLLC.paint.net -s msstore --accept-package-agreements --accept-source-agreements
# choco install -y screentogif
winget install -e -h --id Microsoft.Sysinternals.ZoomIt --accept-package-agreements --accept-source-agreements
winget install -e -h --id WinDirStat.WinDirStat --accept-package-agreements --accept-source-agreements
# winget install -e -h --id Microsoft.BingWallpaper
# winget install -e -h --id Obsidian.Obsidian
winget install -e -h --id JohnMacFarlane.Pandoc
winget install -e -h --id Microsoft.Whiteboard -s msstore --accept-package-agreements --accept-source-agreements
winget install -e -h --id Microsoft.PowerToys --accept-package-agreements --accept-source-agreements # settings to sync
# Already  installed by default
# winget install -e -h --id Microsoft.Teams
# winget install -e -h --id Microsoft.Office
# winget install -e -h --id Logitech.Options
# winget install -e -h --id Dell.DisplayManager
winget install -e -h --id Amazon.Kindle --accept-package-agreements --accept-source-agreements
winget install -e -h --id Trello.Trello --accept-package-agreements --accept-source-agreements
winget install -e -h --id Microsoft.Sysinternals.Suite --accept-package-agreements --accept-source-agreements

# Optional: upgrade all installed winget packages
# winget upgrade --all --accept-package-agreements --accept-source-agreements

# ---------------------------------------------- #
# Dev tools  ----------------------------------- #
# ---------------------------------------------- #
#winget install -e -h --id AndreasWascher.RepoZ
#winget install -e -h --id CoreyButler.NVMforWindows
#iwr https://get.pnpm.io/install.ps1 -useb | iex
# iwr -useb get.scoop.sh | iex
winget install -e -h --id GitHub.cli --accept-package-agreements --accept-source-agreements
winget install -e -h --id Notepad++.Notepad++ --accept-package-agreements --accept-source-agreements
winget install -e -h --id WinMerge.WinMerge --accept-package-agreements --accept-source-agreements
winget install -e -h --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
winget install -e -h --id Git.Git --accept-package-agreements --accept-source-agreements
winget install -e -h --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements

# ---------------------------------------------- #
# Prompt  -------------------------------------- #
# ---------------------------------------------- #
#pwsh -Command { Install-Module posh-git -Scope CurrentUser -Force}
#winget install -e -h --id JanDeDobbeleer.OhMyPosh

# ---------------------------------------------- #
# PowerShell  ---------------------------------- #
# ---------------------------------------------- #
winget install -e -h --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Remove-Item -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Force -ErrorAction SilentlyContinue
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Target "$env:USERPROFILE\dotfiles\config\powerShell\Microsoft.PowerShell_profile.ps1"

# ---------------------------------------------- #
# NuShell  ---------------------------------- #
# ---------------------------------------------- #
# winget install -e -h --id Nushell.Nushell
# saves an initialization script to ~/.oh-my-posh.nu that will be used in Nushell config file
# oh-my-posh init nu --config "$env:USERPROFILE\dotfiles\config\prompt\.oh-my-posh.omp.json"
# Remove-Item -Path "$env:USERPROFILE\AppData\Roaming\nushell\config.nu" -Force
# New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\AppData\Roaming\nushell\config.nu" -Target "$env:USERPROFILE\dotfiles\config\nu\config.nu"
# config auto complete dotnet / nuke / ...

# ---------------------------------------------- #
# Windows Terminal ----------------------------- #
# ---------------------------------------------- #
# Windows Terminal (stable + preview) install with Cascadia Code PL font
winget install -e -h --id Microsoft.WindowsTerminal -s msstore --accept-package-agreements --accept-source-agreements
# winget install -e -h --id Microsoft.WindowsTerminalPreview -s msstore --accept-package-agreements --accept-source-agreements
# choco install -y cascadiacodepl
# Windows terminal configuration
# Remove-Item -Path "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
# New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Target "$env:USERPROFILE\dotfiles\config\windowsTerminal\settings.json"
# cp "$env:USERPROFILE\dotfiles\config\windowsTerminal\icons\*" "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\RoamingState\"
# Windows terminal preview configuration
# Remove-Item -Path "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -Force
# New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -Target "$env:USERPROFILE\dotfiles\config\windowsTerminal\settings.json"
# cp "$env:USERPROFILE\dotfiles\config\windowsTerminal\icons\*" "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\RoamingState\"


# ---------------------------------------------- #
# Blog tools  ---------------------------------- #
# ---------------------------------------------- #
# wyam
# netlify
# statiq
