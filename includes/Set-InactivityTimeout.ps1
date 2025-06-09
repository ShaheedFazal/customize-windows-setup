# Set machine inactivity timeout to 15 minutes (900 seconds)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -Value 900 -Type "DWord" -Force

