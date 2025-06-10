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
# Use today's date to ensure a valid DateTime object across Windows builds
$startTime = (Get-Date).Date.AddHours(21)
try {
    $trigger = New-ScheduledTaskTrigger -Daily -At $startTime `
        -RepetitionInterval (New-TimeSpan -Minutes 15) `
        -RepetitionDuration (New-TimeSpan -Hours 6)
} catch {
    Write-Warning 'Failed to add repetition options. Task will run once per day at 9:00 PM.'
    Write-Log "Fallback simple trigger created due to error: $_"
    $trigger = New-ScheduledTaskTrigger -Daily -At $startTime
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
