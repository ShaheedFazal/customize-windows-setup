Write-Host "Disabling Windows telemetry..."

# Set the most restrictive telemetry level
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type "DWord" -Force

# Disable scheduled telemetry-related tasks
$tasksToDisable = @(
    "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "Microsoft\Windows\Autochk\Proxy",
    "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
)

foreach ($task in $tasksToDisable) {
    try {
        $taskName = Split-Path $task -Leaf
        $taskPath = '\' + (Split-Path $task -Parent) + '\'

        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

        if ($null -ne $existingTask) {
            Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
            Write-Host "[TASK] Disabled: $task" -ForegroundColor Green
        } else {
            Write-Host "[TASK] Not found: $task" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[TASK] Could not disable $task ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

Write-Host "Disabling advertising ID and content suggestions..."

# Migrate user-specific settings to system-wide policies
try {
    $advPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
    if (!(Test-Path $advPath)) {
        New-Item -Path $advPath -Force | Out-Null
    }
    Set-ItemProperty -Path $advPath -Name "DisabledByGroupPolicy" -Type DWord -Value 1
    Write-Host "[OK] Policy applied: Advertising ID disabled for all users"
} catch {
    Write-Host "[WARN] Could not apply advertising ID policy: $($_.Exception.Message)"
}

try {
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (!(Test-Path $cloudPath)) {
        New-Item -Path $cloudPath -Force | Out-Null
    }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 1
    Set-ItemProperty -Path $cloudPath -Name "DisableCloudOptimizedContent" -Type DWord -Value 1
    Write-Host "[OK] Policy applied: Suggested content disabled system-wide"
} catch {
    Write-Host "[WARN] Could not apply content suggestion policy: $($_.Exception.Message)"
}

Write-Host "[OK] Privacy settings strengthened."
