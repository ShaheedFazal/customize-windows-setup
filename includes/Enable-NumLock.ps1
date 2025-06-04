# Enable Num Lock by default for all users
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type String -Value "2"
Set-ItemProperty -Path "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type String -Value "2"
