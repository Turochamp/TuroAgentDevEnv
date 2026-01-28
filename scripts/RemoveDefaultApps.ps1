#--- Uninstall unnecessary applications that come with Windows out of the box ---
Write-Host "Uninstall some applications that come with Windows out of the box" -ForegroundColor "Yellow"

#Referenced to build script
# https://docs.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update
# https://github.com/jayharris/dotfiles-windows/blob/master/windows.ps1#L157
# https://gist.github.com/jessfraz/7c319b046daa101a4aaef937a20ff41f
# https://gist.github.com/alirobe/7f3b34ad89a159e6daa1
# https://github.com/W4RH4WK/Debloat-Windows-10/blob/master/scripts/remove-default-apps.ps1

function removeApp {
	Param ([string]$appName)
	Write-Output "Trying to remove $appName"
	Get-AppxPackage -AllUsers -Name $appName -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
	Get-AppXProvisionedPackage -Online | Where-Object { $_.DisplayName -like $appName } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

$applicationList = @(
	# Windows 11+ consumer apps
	"Clipchamp.Clipchamp"
	"Microsoft.BingNews"
	"Microsoft.BingWeather"
	"Microsoft.GamingApp"
	"Microsoft.GetHelp"
	"Microsoft.Getstarted"
	"Microsoft.MicrosoftOfficeHub"
	"Microsoft.MicrosoftSolitaireCollection"
	"Microsoft.MicrosoftStickyNotes"
	"Microsoft.OutlookForWindows"
	"Microsoft.People"
	"Microsoft.PowerAutomateDesktop"
	"Microsoft.Todos"
	"Microsoft.WindowsAlarms"
	"Microsoft.WindowsCamera"
	"Microsoft.WindowsCommunicationsApps"
	"Microsoft.WindowsFeedbackHub"
	"Microsoft.WindowsMaps"
	"Microsoft.WindowsSoundRecorder"
	"Microsoft.YourPhone"
	"MicrosoftWindows.Client.WebExperience"
	"MicrosoftTeams"
	"Microsoft.ZuneMusic"
	"Microsoft.ZuneVideo"

	# Legacy Windows 10 names (kept for compatibility)
	"Microsoft.3DBuilder"
	"Microsoft.BingSports"
	"Microsoft.CommsPhone"
	"Microsoft.Messaging"
	"Microsoft.OneConnect"
	"Microsoft.WindowsPhone"
	"Microsoft.Office.Sway"
	"Microsoft.XboxApp"
	"Microsoft.XboxIdentityProvider"
	"Microsoft.NetworkSpeedTest"
	"Microsoft.FreshPaint"
	"Microsoft.Print3D"

	# Third-party bundled apps
	"*Autodesk*"
	"*BubbleWitch*"
	"*CandyCrush*"
	"*Facebook*"
	"*Keeper*"
	"*MarchofEmpires*"
	"*Minecraft*"
	"*Netflix*"
	"*Plex*"
	"*Solitaire*"
	"*Twitter*"
	"king.com*"
	"G5*"
	"*.Duolingo-LearnLanguagesforFree"
	"*.EclipseManager"
	"ActiproSoftwareLLC.562882FEEB491" # Code Writer
	"*.AdobePhotoshopExpress"
);

foreach ($app in $applicationList) {
    removeApp $app
}

# Disables suggested apps in the start menu
Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SystemPaneSuggestionsEnabled -Type DWord -Value 0