$taskName = "SmartAutoShutdown"
$scriptPath = "C:\Scripts\check_and_shutdown.ps1"

# Create script folder and script
New-Item -ItemType Directory -Path (Split-Path $scriptPath) -Force | Out-Null

$scriptContent = @'
function Is-UserActive {
    $quser = quser 2>$null
    if ($quser) {
        foreach ($line in $quser) {
            if ($line -match "Active") {
                return $true
            }
        }
    }
    return $false
}

if (-not (Is-UserActive)) {
    shutdown.exe /s /t 60 /c "System shutting down due to inactivity."
}
'@
Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8 -Force

# Remove old task
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Create trigger: start at 9:00 PM and repeat every 15 minutes for 6 hours
# Use a culture-invariant 24-hour time format to avoid localisation issues
# when parsing the start time. Attempt to set the Repetition properties directly.
# On very old PowerShell builds these properties may not exist, in which case the
# task will still run daily at 9:00 PM without the repeat behaviour.
$startTime = [datetime]::ParseExact('21:00', 'HH:mm', $null)
$trigger   = New-ScheduledTaskTrigger -Daily -At $startTime
try {
    $trigger.Repetition.Interval  = New-TimeSpan -Minutes 15
    $trigger.Repetition.Duration = New-TimeSpan -Hours 6
} catch {
    Write-Log "Failed to set repetition property on shutdown trigger: $_"
    Write-Warning 'Task will run once per day at 9:00 PM without repetition.'
}

# Define action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Register task under SYSTEM
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Description "Shuts down when no users are active after 9PM"
    Write-Host "[OK] Smart auto-shutdown task created successfully" -ForegroundColor Green
} catch {
    Write-Warning "Failed to register shutdown task: $_"
    Write-Log "Failed to register shutdown task: $_"
}
