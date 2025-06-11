# Disable Windows 11 Widgets

# Hide Widgets button for the current user
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type "DWord" -Force

# Apply system-wide policy to disable Widgets
$widgetsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
if (Set-RegistryValue -Path $widgetsPolicy -Name "AllowNewsAndInterests" -Value 0 -Type "DWord" -Force) {
    Write-Host "[OK] Policy applied: Widgets disabled system-wide"
} else {
    Write-Host "[WARN] Could not apply widgets policy" -ForegroundColor Yellow
}
