# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Hide recently and frequently used item shortcuts in Explorer
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0 -Type "DWord" -Force
