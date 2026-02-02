# Enable Action Center
# Set policies to explicitly enable notifications for all users
Write-Host "Enabling Action Center notifications..."

$explorerPathHKCU = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
$explorerPathHKLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"

Set-RegistryValue -Path $explorerPathHKCU -Name "DisableNotificationCenter" -Value 0 -Type "DWord"
Set-RegistryValue -Path $explorerPathHKLM -Name "DisableNotificationCenter" -Value 0 -Type "DWord"
