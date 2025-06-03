# Configure Clipboard Settings

# ✅ Enable Clipboard History (Win + V)
Write-Host "Enabling Clipboard History..."
reg add "HKCU\Software\Microsoft\Clipboard" /v EnableClipboardHistory /t REG_DWORD /d 1 /f

# ❌ Disable Clipboard Sync Across Devices
Write-Host "Disabling Clipboard Sync Across Devices..."
reg add "HKCU\Software\Microsoft\Clipboard" /v EnableCloudClipboard /t REG_DWORD /d 0 /f
