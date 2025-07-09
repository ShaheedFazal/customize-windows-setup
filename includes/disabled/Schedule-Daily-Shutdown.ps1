# Configure a daily auto-shutdown task that checks for user inactivity

param(
    [string]$StartTime = "9:00PM",
    [string]$ScriptDirectory = "C:\Scripts",
    [int]$IdleTimeoutMinutes = 30,
    # Default Zapier webhook used for shutdown notifications
    [string]$WebhookUrl = ""
)

# Ensure the helper script directory exists
if (-not (Test-Path -Path $ScriptDirectory -PathType Container)) {
    Write-Host "Creating directory: $ScriptDirectory"
    New-Item -Path $ScriptDirectory -ItemType Directory -Force | Out-Null
}

$helperPath = Join-Path -Path $ScriptDirectory -ChildPath "check_and_shutdown_idle.ps1"

# --- Helper Script Content with Idle Time Check and Optional Webhook ---
$helperContent = @"
# Suppress errors in case the type is already loaded
`$ErrorActionPreference = 'SilentlyContinue'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public struct LASTINPUTINFO
{
    public uint cbSize;
    public uint dwTime;
}

public class UserIdleTime
{
    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleTime()
    {
        LASTINPUTINFO lastInput = new LASTINPUTINFO();
        lastInput.cbSize = (uint)Marshal.SizeOf(lastInput);
        GetLastInputInfo(ref lastInput);

        return ((uint)Environment.TickCount - lastInput.dwTime);
    }
}
'@
`$ErrorActionPreference = 'Continue'

function Send-WebhookNotification {
    param(
        [string]`$Uri,
        [int]`$IdleMinutes,
        [int]`$MaxIdleMinutes
    )

    if ([string]::IsNullOrEmpty(`$Uri)) { return }

    `$payload = @{
        text     = "Shutting down computer due to inactivity."
        username = "Smart Shutdown Bot"
        attachments = @(
            @{
                fallback = "Shutdown initiated for `$env:COMPUTERNAME."
                color    = "warning"
                fields   = @(
                    @{ title = "Computer Name";    value = `$env:COMPUTERNAME;            short = `$true }
                    @{ title = "Detected Idle Time"; value = "`$IdleMinutes minutes";     short = `$true }
                    @{ title = "Configured Timeout"; value = "`$MaxIdleMinutes minutes"; short = `$true }
                    @{ title = "Timestamp";         value = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); short = `$true }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri `$Uri -Method Post -Body `$payload -ContentType 'application/json'
    } catch {
        Write-Warning "Failed to send webhook notification. Error: `$_"
    }
}

function Check-SystemIdle {
    param([int]`$MaxIdleMinutes)

    `$interactiveSession = Get-CimInstance -ClassName Win32_LogonSession | Where-Object { `$_.LogonType -eq 2 }

    if (-not `$interactiveSession) {
        return @{ IsIdle = `$true; IdleMinutes = -1 }
    }

    `$idleMs = [UserIdleTime]::GetIdleTime()
    `$idleMinutes = [math]::Round(`$idleMs / 60000)

    if (`$idleMinutes -ge `$MaxIdleMinutes) {
        return @{ IsIdle = `$true; IdleMinutes = `$idleMinutes }
    }

    return @{ IsIdle = `$false }
}

[string]`$WebhookUrl = '$WebhookUrlPlaceholder'
[int]`$IdleTimeoutMinutes = $IdleTimeoutMinutesPlaceholder

`$result = Check-SystemIdle -MaxIdleMinutes `$IdleTimeoutMinutes

if (`$result.IsIdle) {
    Send-WebhookNotification -Uri `$WebhookUrl -IdleMinutes `$result.IdleMinutes -MaxIdleMinutes `$IdleTimeoutMinutes
    Start-Process "shutdown.exe" -ArgumentList "/s /f /t 60 /c 'System has been idle for too long and will now shut down.'" -NoNewWindow
}
"@

# Inject user parameters into the helper script content
$helperFinal = $helperContent.Replace('$IdleTimeoutMinutesPlaceholder', $IdleTimeoutMinutes)
$helperFinal = $helperFinal.Replace('$WebhookUrlPlaceholder', $WebhookUrl)

$helperFinal | Out-File -FilePath $helperPath -Encoding utf8 -Force

# --- Use COM Object for Reliable Task Scheduling (borrowed from first script) ---
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
    
    # Parse the start time parameter
    $startTime = [DateTime]::Parse($StartTime)
    $todayStart = (Get-Date).Date.Add($startTime.TimeOfDay)
    
    $trigger.StartBoundary = $todayStart.ToString("yyyy-MM-dd'T'HH:mm:ss")
    $trigger.DaysInterval = 1
    $trigger.Repetition.Interval = "PT15M" # 15 Minutes
    $trigger.Repetition.Duration = "PT6H"  # 6 Hours

    # 6. Define the Action
    $action = $taskDefinition.Actions.Create(0) # Execute a program
    $action.Path = "powershell.exe"
    $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$helperPath`""

    # 7. Define the task settings
    $taskDefinition.Settings.Enabled = $true
    $taskDefinition.Settings.StopIfGoingOnBatteries = $false
    $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
    $taskDefinition.Settings.AllowHardTerminate = $true
    $taskDefinition.Settings.StartWhenAvailable = $true

    # 8. Register the Task (Create or Update)
    # First, delete any old version of the task.
    try {
        $rootFolder.DeleteTask("SmartAutoShutdown", 0)
        Write-Host "[INFO] Removed old version of the task." -ForegroundColor Cyan
    } catch {
        # This is fine, it just means the task didn't exist before.
    }
    
    # Register the new task and suppress the output object.
    $rootFolder.RegisterTaskDefinition(
        "SmartAutoShutdown",
        $taskDefinition,
        6,
        "S-1-5-18",
        $null,
        1
    ) | Out-Null

    Write-Host "[OK] Smart auto-shutdown task created successfully." -ForegroundColor Green
    Write-Host "Scheduled task 'SmartAutoShutdown' created. Starts at $StartTime and shuts down after $IdleTimeoutMinutes minutes of inactivity."
    if (-not [string]::IsNullOrEmpty($WebhookUrl)) {
        Write-Host "A webhook notification will be sent before shutdown."
    }

} catch {
    Write-Error "A critical error occurred while creating the task: $($_.Exception.Message)"
}
