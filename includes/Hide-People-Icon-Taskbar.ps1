# Hide Taskbar People icon via policy for all users
# Apply system-wide policy and remove any per-user setting
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -Type "DWord" -Force
Remove-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand"

