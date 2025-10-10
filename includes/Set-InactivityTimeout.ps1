# Set machine inactivity timeout to 30 minutes (1800 seconds)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -Value 1800 -Type "DWord" -Force

