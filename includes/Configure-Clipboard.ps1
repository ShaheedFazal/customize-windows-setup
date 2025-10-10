# Configure Clipboard Settings

# Enable clipboard history and disable cross-device sync for all users
Write-Host "Configuring clipboard policy..." -ForegroundColor Cyan

try {
    # Set system-wide policy to allow clipboard history
    $systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    Set-RegistryValue -Path $systemPath -Name "AllowClipboardHistory" -Value 1 -Type "DWord" -Force
    Set-RegistryValue -Path $systemPath -Name "AllowCrossDeviceClipboard" -Value 0 -Type "DWord" -Force
    Write-Host "[POLICY] Clipboard history allowed, cross-device sync disabled" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Could not apply clipboard policy: $_" -ForegroundColor Red
}

# Enable clipboard history for all loaded user profiles
Write-Host "[USERS] Enabling clipboard history for all user profiles..." -ForegroundColor Yellow

$usersConfigured = 0
Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -notmatch '_Classes$' } | ForEach-Object {
    $userSID = $_.PSChildName
    $clipboardPath = "Registry::HKEY_USERS\$userSID\Software\Microsoft\Clipboard"

    try {
        Set-RegistryValue -Path $clipboardPath -Name "EnableClipboardHistory" -Value 1 -Type "DWord" -Force
        $usersConfigured++

        # Identify which user this is
        if ($userSID -eq ".DEFAULT") {
            Write-Host "  [OK] Enabled for default user template (new accounts)" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Enabled for user SID: $userSID" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] Failed for SID $userSID : $_" -ForegroundColor Red
    }
}

Write-Host "[CLIPBOARD] ✅ Clipboard history enabled for $usersConfigured user profile(s)" -ForegroundColor Green
