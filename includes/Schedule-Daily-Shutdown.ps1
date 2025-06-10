# --- Define Script Variables ---
$taskName = "SmartAutoShutdown"
$scriptPath = "C:\Scripts\check_and_shutdown.ps1"

# --- Create Script Folder and Script Content ---
New-Item -ItemType Directory -Path (Split-Path $scriptPath) -Force | Out-Null

$scriptContent = @'
function Is-UserActive {
    $quserOutput = quser 2>$null
    if ($quserOutput) {
        foreach ($line in $quserOutput) {
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

# --- Use the Scheduler Service COM Object for Maximum Reliability ---
try {
    Write-Host "[INFO] Using the COM object to build the scheduled task..." -ForegroundColor Cyan

    # 1. Connect to the Task Scheduler Service
    $schedule = New-Object -ComObject "Schedule.Service"
    $schedule.Connect()

    # 2. Get the root folder ('\') where tasks are stored
    $rootFolder = $schedule.GetFolder("\")

    # 3. Define the Task's core properties
    $taskDefinition = $schedule.NewTask(0)

    # 4. Set the Principal (who the task runs as)
    $taskDefinition.Principal.UserId = "S-1-5-18" # SYSTEM account
    $taskDefinition.Principal.RunLevel = 1       # Highest Privileges

    # 5. Define the Trigger
    $trigger = $taskDefinition.Triggers.Create(2) # Daily trigger
    $startTime = (Get-Date).Date.AddHours(21)
    $trigger.StartBoundary = $startTime.ToString("yyyy-MM-dd'T'HH:mm:ss")
    $trigger.DaysInterval = 1
    $trigger.Repetition.Interval = "PT15M" # 15 Minutes
    $trigger.Repetition.Duration = "PT6H"  # 6 Hours

    # 6. Define the Action
    $action = $taskDefinition.Actions.Create(0) # Execute a program
    $action.Path = "powershell.exe"
    $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

    # 7. Define the task settings
    $taskDefinition.Settings.Enabled = $true
    $taskDefinition.Settings.StopIfGoingOnBatteries = $false
    $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
    $taskDefinition.Settings.AllowHardTerminate = $true
    $taskDefinition.Settings.StartWhenAvailable = $true

    # 8. Register the Task (Create or Update)
    # First, delete any old version of the task.
    try {
        $rootFolder.DeleteTask($taskName, 0)
        Write-Host "[INFO] Removed old version of the task." -ForegroundColor Cyan
    } catch {
        # This is fine, it just means the task didn't exist before.
    }
    
    # Register the new task and suppress the output object.
    $rootFolder.RegisterTaskDefinition(
        $taskName,
        $taskDefinition,
        6,
        "S-1-5-18",
        $null,
        1
    ) | Out-Null

    Write-Host "[OK] Smart auto-shutdown task created successfully." -ForegroundColor Green

} catch {
    Write-Error "A critical error occurred while creating the task: $($_.Exception.Message)"
}
