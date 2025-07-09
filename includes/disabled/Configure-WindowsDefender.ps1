# Enable Windows Defender real-time protection
Set-MpPreference -DisableRealtimeMonitoring $false

# Enable additional Defender protections
Set-MpPreference -DisableBehaviorMonitoring $false
Set-MpPreference -DisableIOAVProtection $false
Set-MpPreference -DisableScriptScanning $false

# Enable cloud-based protection
Set-MpPreference -MAPSReporting Advanced

# Enable automatic sample submission
Set-MpPreference -SubmitSamplesConsent 1
