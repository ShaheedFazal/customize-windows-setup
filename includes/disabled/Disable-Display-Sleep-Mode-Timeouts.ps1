# Disable display and sleep mode timeouts
# Note: Use either this script or Set-PowerManagement-HighPerformance.ps1, not both, as they could conflict.
powercfg /X monitor-timeout-ac 0
powercfg /X monitor-timeout-dc 0
powercfg /X standby-timeout-ac 0
powercfg /X standby-timeout-dc 0
