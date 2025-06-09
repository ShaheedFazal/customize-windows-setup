# Disable OneDrive
Write-Output "Disabling OneDrive..."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -Type "DWord"

