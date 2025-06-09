# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Hide Taskbar People icon
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -Type "DWord" -Force
