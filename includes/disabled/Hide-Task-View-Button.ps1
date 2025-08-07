# Hide Task View button system-wide via policy
Write-Host "Hiding Task View button on the taskbar system-wide..."

$policyRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows"
New-Item -Path $policyRoot -Name "Explorer" -Force | Out-Null
$policyPath = "$policyRoot\Explorer"

Set-RegistryValue -Path $policyPath -Name "ShowTaskViewButton" -Value 0 -Type "DWord" -Force
