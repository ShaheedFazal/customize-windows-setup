# Configure the default Windows screen saver, enforce a 15 minute timeout, and require a password on resume

$screenSaver = "$env:windir\System32\scrnsave.scr"
$desktopPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"

Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveActive" -Value "1" -Type "String"
Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveTimeOut" -Value "900" -Type "String"
Set-RegistryValue -Path $desktopPolicy -Name "SCRNSAVE.EXE" -Value $screenSaver -Type "String"
Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaverIsSecure" -Value "1" -Type "String"

