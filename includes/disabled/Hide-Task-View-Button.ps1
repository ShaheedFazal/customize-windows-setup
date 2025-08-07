# Hide Task View button for all users via policy
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "ShowTaskViewButton" -Value 0 -Type "DWord" -Force
