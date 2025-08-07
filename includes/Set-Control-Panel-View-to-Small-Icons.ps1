# Set Control Panel view to Small icons (Classic)
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\ControlPanel"

if (-not (Test-Path $policyPath)) {
    New-Item -Path $policyPath -Force | Out-Null
}

Set-RegistryValue -Path $policyPath -Name "StartupPage" -Value 1 -Type "DWord"
Set-RegistryValue -Path $policyPath -Name "AllItemsIconView" -Value 1 -Type "DWord"
