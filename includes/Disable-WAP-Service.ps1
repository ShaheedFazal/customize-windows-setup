# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Stopping and disabling WAP Push Service
Stop-ServiceSafely -ServiceName "dmwappushservice" -DisplayName "WAP Push Service"
Set-ServiceStartupTypeSafely -ServiceName "dmwappushservice" -StartupType "Disabled" -DisplayName "WAP Push Service"
