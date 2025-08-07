# Show all tray icons
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "EnableAutoTray" -Value 0 -Type "DWord" -Force
