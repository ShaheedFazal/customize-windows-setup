# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Disable Bing Search
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1 -Type "DWord" -Force
