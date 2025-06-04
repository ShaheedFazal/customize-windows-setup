# Create a custom folder for Photos screen saver images and set screen saver timeout

$ScreenSaverFolder = "C:\\Screensaver"
if (!(Test-Path $ScreenSaverFolder)) {
    New-Item -ItemType Directory -Path $ScreenSaverFolder | Out-Null
}

$photoScr = "$env:windir\System32\PhotoScreensaver.scr"

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Type String -Value "1"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Type String -Value "600"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Type String -Value $photoScr

$photosKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\Photos"
if (!(Test-Path $photosKey)) {
    New-Item -Path $photosKey | Out-Null
}
Set-ItemProperty -Path $photosKey -Name "ImageDirectory" -Type String -Value $ScreenSaverFolder

