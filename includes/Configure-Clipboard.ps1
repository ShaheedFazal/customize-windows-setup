# Configure Clipboard Settings

# Enable clipboard history and disable cross-device sync for all users
Write-Host "Configuring clipboard policy..."
try {
    $systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (!(Test-Path $systemPath)) {
        New-Item -Path $systemPath -Force | Out-Null
    }
    Set-ItemProperty -Path $systemPath -Name "AllowClipboardHistory" -Type DWord -Value 1
    Set-ItemProperty -Path $systemPath -Name "AllowCrossDeviceClipboard" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Clipboard history enabled, cross-device sync disabled"
} catch {
    Write-Host "[WARN] Could not apply clipboard policy: $($_.Exception.Message)"
}
