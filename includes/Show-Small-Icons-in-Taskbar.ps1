# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Show small icons in taskbar
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSmallIcons" -Value 1 -Type "DWord" -Force
