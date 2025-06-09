# Disable Fast Startup to ensure proper WoL functionality and clean shutdown

Write-Host "Disabling Fast Startup..."

try {
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type "DWord" -Force
    Write-Host "Fast Startup disabled successfully."
} catch {
    Write-Host "Failed to disable Fast Startup: $_"
}

Write-Host "Fast Startup configuration complete."

