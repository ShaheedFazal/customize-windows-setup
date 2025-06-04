# Set machine inactivity timeout to 15 minutes (900 seconds)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs /t REG_DWORD /d 900 /f
