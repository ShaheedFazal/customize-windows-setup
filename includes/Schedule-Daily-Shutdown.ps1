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

# Create trigger: start at 9:00 PM, repeat every 15 mins, for 6 hours
$trigger = New-ScheduledTaskTrigger -Daily -At 21:00 -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Hours 6)

# Define action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Register task under SYSTEM
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Description "Shuts down when no users are active after 9PM"
