# Show recently and frequently used item shortcuts in Explorer
$explorerPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (!(Test-Path $explorerPolicyPath)) {
    New-Item -Path $explorerPolicyPath -Force | Out-Null
}
Set-RegistryValue -Path $explorerPolicyPath -Name "ShowRecent" -Value 1 -Type "DWord" -Force
Set-RegistryValue -Path $explorerPolicyPath -Name "ShowFrequent" -Value 1 -Type "DWord" -Force
