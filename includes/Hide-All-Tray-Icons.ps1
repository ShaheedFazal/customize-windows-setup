# Hide all tray icons
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "EnableAutoTray" -Value 1 -Type "DWord" -Force
