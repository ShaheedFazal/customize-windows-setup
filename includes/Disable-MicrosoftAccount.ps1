# Block Microsoft account sign-in prompts
Write-Host "Blocking Microsoft account sign-in prompts..."
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 3 /f

# Disable Microsoft account creation
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 1 /f

# Disable Microsoft 365 promotional notifications
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f
