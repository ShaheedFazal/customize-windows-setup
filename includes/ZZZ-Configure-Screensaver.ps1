# Create a custom folder for Photos screen saver images and set screen saver timeout

$ScreenSaverFolder = "C:\\Screensaver"
if (!(Test-Path $ScreenSaverFolder)) {
    New-Item -ItemType Directory -Path $ScreenSaverFolder | Out-Null
}

$photoScr = "$env:windir\System32\PhotoScreensaver.scr"

Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "600" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value $photoScr -Type "String"

$photosKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\Photos"
Set-RegistryValue -Path $photosKey -Name "ImageDirectory" -Value $ScreenSaverFolder -Type "String"

