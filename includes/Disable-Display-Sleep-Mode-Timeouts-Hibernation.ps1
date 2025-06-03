# Disable display and sleep mode timeouts
powercfg /X monitor-timeout-ac 0
powercfg /X monitor-timeout-dc 0
powercfg /X standby-timeout-ac 0
powercfg /X standby-timeout-dc 0

# Disable hibernation (reclaims disk space, avoids hybrid sleep issues)
powercfg -h off
Write-Host "✅ Hibernation disabled to prevent hybrid sleep and reclaim disk space."
