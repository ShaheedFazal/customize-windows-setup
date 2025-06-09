# Disable Action Center
# Migrate from HKCU to HKLM so notifications are disabled for all users
Write-Host "Disabling Action Center notifications..."

try {
    $explorerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (!(Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }
    Set-ItemProperty -Path $explorerPath -Name "DisableNotificationCenter" -Type DWord -Value 1
    Write-Host "[OK] Policy applied: Action Center disabled system-wide"
} catch {
    Write-Host "[WARN] Could not disable Action Center: $($_.Exception.Message)"
}

try {
    $pushPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (!(Test-Path $pushPath)) {
        New-Item -Path $pushPath -Force | Out-Null
    }
    Set-ItemProperty -Path $pushPath -Name "ToastEnabled" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Toast notifications disabled"
} catch {
    Write-Host "[WARN] Could not disable toast notifications: $($_.Exception.Message)"
}
