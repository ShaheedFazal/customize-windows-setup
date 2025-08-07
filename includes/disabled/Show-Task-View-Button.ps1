# Show Task View button system-wide via policy
Write-Host "Showing Task View button on the taskbar system-wide..."

$policyRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows"
New-Item -Path $policyRoot -Name "Explorer" -Force | Out-Null
$policyPath = "$policyRoot\Explorer"

Set-RegistryValue -Path $policyPath -Name "ShowTaskViewButton" -Value 1 -Type "DWord" -Force
