# Show all tray icons
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoAutoTrayNotify" -Value 1 -Type "DWord" -Force
