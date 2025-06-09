# Configure Clipboard Settings

# Enable Clipboard History (Win + V)
Write-Host "Enabling Clipboard History..."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type "DWord" -Force

# Disable Clipboard Sync Across Devices
Write-Host "Disabling Clipboard Sync Across Devices..."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableCloudClipboard" -Value 0 -Type "DWord" -Force
