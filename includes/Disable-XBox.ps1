# Disable Xbox features
Get-AppxPackage "Microsoft.XboxApp" | Remove-AppxPackage
Get-AppxPackage "Microsoft.XboxIdentityProvider" | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage "Microsoft.XboxSpeechToTextOverlay" | Remove-AppxPackage
Get-AppxPackage "Microsoft.XboxGameOverlay" | Remove-AppxPackage
Get-AppxPackage "Microsoft.Xbox.TCUI" | Remove-AppxPackage
# Apply system-wide policy to disable Game DVR
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type "DWord"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" -Name "value" -Value 0 -Type "DWord"
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\ApplicationManagement\AllowGameDVR" -Name "value" -Value 0 -Type "DWord"

# Clean up any per-user Game DVR settings
$hives = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-' -and $_.PSChildName -notmatch '_Classes$' }
foreach ($hive in $hives) {
    $userPath = "Registry::$($hive.PSChildName)\System\GameConfigStore"
    Remove-RegistryValue -Path $userPath -Name 'GameDVR_Enabled'
}

Remove-RegistryValue -Path 'HKU:\.DEFAULT\System\GameConfigStore' -Name 'GameDVR_Enabled'
