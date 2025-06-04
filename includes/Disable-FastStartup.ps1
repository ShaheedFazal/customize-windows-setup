# Disable Fast Startup to ensure proper WoL functionality and clean shutdown

Write-Host "[INFO] Disabling Fast Startup..."

try {
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f
    Write-Host "[OK] Fast Startup disabled successfully."
} catch {
    Write-Host "[ERROR] Failed to disable Fast Startup: $_"
}

Write-Host "[DONE] Fast Startup configuration complete."
