# Show Task View button for all users via policy
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "ShowTaskViewButton" -Value 1 -Type "DWord" -Force