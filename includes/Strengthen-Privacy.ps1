# Load shared functions
. "$PSScriptRoot\Registry-Functions.ps1"

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
        Disable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
        Write-Host "[TASK] Disabled: $task" -ForegroundColor Green
    } catch {
        Write-Host "[TASK] Could not disable $task (may not exist)" -ForegroundColor Yellow
    }
}

Write-Host "Disabling advertising ID and content suggestions..."

# Disable advertising ID
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type "DWord" -Force

# Disable suggested content and tips in Windows UI
$cdmPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-RegistryValue -Path $cdmPath -Name "SubscribedContent-338388Enabled" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path $cdmPath -Name "SoftLandingEnabled" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path $cdmPath -Name "SubscribedContent-310093Enabled" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path $cdmPath -Name "SubscribedContent-338389Enabled" -Value 0 -Type "DWord" -Force
Set-RegistryValue -Path $cdmPath -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type "DWord" -Force

Write-Host "[OK] Privacy settings strengthened."
