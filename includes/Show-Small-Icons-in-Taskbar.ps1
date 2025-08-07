# Show small icons in taskbar
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "TaskbarSmallIcons" -Value 1 -Type "DWord" -Force
