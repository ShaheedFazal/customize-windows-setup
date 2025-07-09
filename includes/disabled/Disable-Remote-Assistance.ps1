# Disable Remote Assistance - Not applicable to Server (unless Remote Assistance is explicitly installed)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -Type "DWord"
