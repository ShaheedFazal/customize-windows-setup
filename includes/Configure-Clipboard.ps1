# Configure Clipboard Settings

# Enable Clipboard History (Win + V)
Write-Host "Enabling Clipboard History..."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type "DWord" -Force

# Disable Clipboard Sync Across Devices
Write-Host "Disabling Clipboard Sync Across Devices..."
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
