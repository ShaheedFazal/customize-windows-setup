# Configure Windows screen saver with 15 minute timeout and require password on resume

# Use the blank screensaver (just turns screen black) - available in all Windows versions
$screenSaver = "$env:windir\System32\scrnsave.scr"
$blankScreenSaver = "$env:windir\System32\scrnsave.exe"

# Check which screensaver exists and use it
if (Test-Path $blankScreenSaver) {
    $screenSaverToUse = $blankScreenSaver
    Write-Host "[SCREENSAVER] Using blank screensaver: $screenSaverToUse"
} elseif (Test-Path "$env:windir\System32\ssText3d.scr") {
    $screenSaverToUse = "$env:windir\System32\ssText3d.scr"
    Write-Host "[SCREENSAVER] Using 3D text screensaver: $screenSaverToUse"
} else {
    # Fallback - just enable screen lock without screensaver animation
    $screenSaverToUse = ""
    Write-Host "[SCREENSAVER] No screensaver found - will use screen lock only"
}

$desktopPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"

# Enable screensaver
Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveTimeOut" -Value "900" -Type "String" -Force

# Set screensaver executable if one exists
if ($screenSaverToUse -ne "") {
    Set-RegistryValue -Path $desktopPolicy -Name "SCRNSAVE.EXE" -Value $screenSaverToUse -Type "String" -Force
}

# Require password on resume (this is the important security setting)
Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force

# Also set user-level setting to ensure password requirement works
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force

Write-Host "[SCREENSAVER] Configured 15-minute screensaver with password protection"

