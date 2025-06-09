# Disabling Feedback
try {
    $feedbackPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (!(Test-Path $feedbackPath)) {
        New-Item -Path $feedbackPath -Force | Out-Null
    }
    Set-ItemProperty -Path $feedbackPath -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1
    Write-Host "[OK] Policy applied: Feedback notifications disabled"
} catch {
    Write-Host "[WARN] Could not apply feedback policy: $($_.Exception.Message)"
}

try {
    $telemetryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    if (!(Test-Path $telemetryPath)) {
        New-Item -Path $telemetryPath -Force | Out-Null
    }
    Set-ItemProperty -Path $telemetryPath -Name "AllowTelemetry" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Telemetry level set to 0"
} catch {
    Write-Host "[WARN] Could not apply telemetry policy: $($_.Exception.Message)"
}

Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClient" -ErrorAction SilentlyContinue | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" -ErrorAction SilentlyContinue | Out-Null
