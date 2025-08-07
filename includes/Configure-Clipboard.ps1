# Configure Clipboard Settings

# Enable clipboard history and disable cross-device sync for all users
Write-Host "Configuring clipboard policy..."
try {
    # Set system-wide policy to allow clipboard history
    $systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (!(Test-Path $systemPath)) {
        New-Item -Path $systemPath -Force | Out-Null
    }
    Set-ItemProperty -Path $systemPath -Name "AllowClipboardHistory" -Type DWord -Value 1
    Set-ItemProperty -Path $systemPath -Name "AllowCrossDeviceClipboard" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Clipboard history allowed, cross-device sync disabled"
} catch {
    Write-Host "[WARN] Could not apply clipboard policy: $($_.Exception.Message)"
}

# Enable clipboard history at user level for current user and default profile
Write-Host "Enabling clipboard history for users..."
try {
    # Enable for current user
    $clipboardPath = "HKCU:\Software\Microsoft\Clipboard"
    Set-RegistryValue -Path $clipboardPath -Name "EnableClipboardHistory" -Value 1 -Type "DWord" -Force
    
    Write-Host "[OK] Clipboard history enabled for current user"
} catch {
    Write-Host "[WARN] Could not enable clipboard history for current user: $_"
}
