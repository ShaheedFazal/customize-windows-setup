# Disable Autoplay globally
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Type "DWord" -Force
