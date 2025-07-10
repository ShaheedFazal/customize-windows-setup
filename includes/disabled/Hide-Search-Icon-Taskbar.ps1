# Hide Taskbar Search icon / box
# Use Explorer policy to apply setting system-wide instead of per-user HKCU
Write-Host "Hiding search box on the taskbar for all users..."

try {
    $explorerPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (!(Test-Path $explorerPolicy)) {
        New-Item -Path $explorerPolicy -Force | Out-Null
    }
    Set-ItemProperty -Path $explorerPolicy -Name "SearchBoxTaskbarMode" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Taskbar search box hidden"
} catch {
    Write-Host "[WARN] Could not hide taskbar search box: $($_.Exception.Message)"
}
