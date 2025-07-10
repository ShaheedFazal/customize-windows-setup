# Hide Widgets icon on the taskbar for all users using policy keys
Write-Host "Hiding Widgets icon on the taskbar system-wide..."

$policyManagerPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"
$dshPolicyPath     = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"

try {
    # Confirm the policy path is writable
    $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests', $true)
    if (-not $regKey) {
        throw "Registry path could not be opened with write access"
    }
    $regKey.Close()

    Set-RegistryValue -Path $policyManagerPath -Name "value" -Value 0 -Type "DWord" -Force
    Set-RegistryValue -Path $dshPolicyPath -Name "AllowNewsAndInterests" -Value 0 -Type "DWord" -Force
    Write-Host "[OK] Policy applied: Widgets icon hidden"
} catch {
    Write-Warning "Unable to modify Widgets policy settings. UAC or group policy may restrict write access. Try running PowerShell as Administrator. $_"
}
