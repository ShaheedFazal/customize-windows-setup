if (Test-MachineWideSentinel -Name 'Hide-All-Tray-Icons') { return }

# Hide all tray icons
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "EnableAutoTray" -Value 1 -Type "DWord" -Force
