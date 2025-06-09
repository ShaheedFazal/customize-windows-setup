# Disabling Cortana
try {
    $inputPath = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
    if (!(Test-Path $inputPath)) {
        New-Item -Path $inputPath -Force | Out-Null
    }
    Set-ItemProperty -Path $inputPath -Name "AllowInputPersonalization" -Type DWord -Value 0
    Set-ItemProperty -Path $inputPath -Name "RestrictImplicitTextCollection" -Type DWord -Value 1
    Set-ItemProperty -Path $inputPath -Name "RestrictImplicitInkCollection" -Type DWord -Value 1
    Write-Host "[OK] Policy applied: Input personalization disabled system-wide"
} catch {
    Write-Host "[WARN] Could not apply input personalization policy: $($_.Exception.Message)"
}

# Continue enforcing Cortana disable policy
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type "DWord" -Force
