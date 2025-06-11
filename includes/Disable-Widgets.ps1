# Disable Windows 11 Widgets

# Hide Widgets button for the current user
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type "DWord" -Force

# Apply system-wide policy to disable Widgets
try {
    $widgetsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (!(Test-Path $widgetsPolicy)) {
        New-Item -Path $widgetsPolicy -Force | Out-Null
    }
    Set-ItemProperty -Path $widgetsPolicy -Name "AllowNewsAndInterests" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Widgets disabled system-wide"
} catch {
    Write-Host "[WARN] Could not apply widgets policy: $($_.Exception.Message)"
}
