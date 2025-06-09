# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

# Stopping and disabling Diagnostics Tracking Service
Stop-ServiceSafely -ServiceName "DiagTrack" -DisplayName "Diagnostics Tracking Service"
Set-ServiceStartupTypeSafely -ServiceName "DiagTrack" -StartupType "Disabled" -DisplayName "Diagnostics Tracking Service"
