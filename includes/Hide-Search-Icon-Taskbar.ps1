# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Hide Taskbar Search icon / box
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type "DWord" -Force
