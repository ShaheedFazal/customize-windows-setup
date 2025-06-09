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
# Older PowerShell versions (e.g. 5.1) don't expose the Repetition property
# on the trigger object, so the interval and duration must be set when the
# trigger is created.
$trigger = New-ScheduledTaskTrigger -Daily -At "9:00 PM" `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Hours 6)

# Define action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Register task under SYSTEM
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Description "Shuts down when no users are active after 9PM"

Write-Host "[OK] Smart auto-shutdown task created successfully" -ForegroundColor Green
