# Disable hibernation (reclaims disk space, avoids hybrid sleep issues)
powercfg.exe -h off
Write-Host "[OK] Hibernation disabled to prevent hybrid sleep and reclaim disk space."
