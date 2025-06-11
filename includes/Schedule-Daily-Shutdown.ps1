# Configure a daily auto-shutdown task that checks for user inactivity

param(
    [string]$StartTime = "9:00PM",
    [string]$ScriptDirectory = "C:\Scripts",
    [int]$IdleTimeoutMinutes = 30,
    # Default Zapier webhook used for shutdown notifications
    [string]$WebhookUrl = "https://hooks.zapier.com/hooks/catch/45778/uyf4gr8/"
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
$ErrorActionPreference = 'SilentlyContinue'

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
$ErrorActionPreference = 'Continue'

function Send-WebhookNotification {
    param(
        [string]$Uri,
        [int]$IdleMinutes,
        [int]$MaxIdleMinutes
    )

    if ([string]::IsNullOrEmpty($Uri)) { return }

    $payload = @{
        text     = "Shutting down computer due to inactivity."
        username = "Smart Shutdown Bot"
        attachments = @(
            @{
                fallback = "Shutdown initiated for $env:COMPUTERNAME."
                color    = "warning"
                fields   = @(
                    @{ title = "Computer Name";    value = $env:COMPUTERNAME;            short = $true }
                    @{ title = "Detected Idle Time"; value = "$IdleMinutes minutes";     short = $true }
                    @{ title = "Configured Timeout"; value = "$MaxIdleMinutes minutes"; short = $true }
                    @{ title = "Timestamp";         value = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); short = $true }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $Uri -Method Post -Body $payload -ContentType 'application/json'
    } catch {
        Write-Warning "Failed to send webhook notification. Error: $_"
    }
}

function Check-SystemIdle {
    param([int]$MaxIdleMinutes)

    $interactiveSession = Get-CimInstance -ClassName Win32_LogonSession | Where-Object { $_.LogonType -eq 2 }

    if (-not $interactiveSession) {
        return @{ IsIdle = $true; IdleMinutes = -1 }
    }

    $idleMs = [UserIdleTime]::GetIdleTime()
    $idleMinutes = [math]::Round($idleMs / 60000)

    if ($idleMinutes -ge $MaxIdleMinutes) {
        return @{ IsIdle = $true; IdleMinutes = $idleMinutes }
    }

    return @{ IsIdle = $false }
}

[string]$WebhookUrl = '$WebhookUrlPlaceholder'
[int]$IdleTimeoutMinutes = $IdleTimeoutMinutesPlaceholder

$result = Check-SystemIdle -MaxIdleMinutes $IdleTimeoutMinutes

if ($result.IsIdle) {
    Send-WebhookNotification -Uri $WebhookUrl -IdleMinutes $result.IdleMinutes -MaxIdleMinutes $IdleTimeoutMinutes
    Start-Process "shutdown.exe" -ArgumentList "/s /f /t 60 /c 'System has been idle for too long and will now shut down.'" -NoNewWindow
}
"@

# Inject user parameters into the helper script content
$helperFinal = $helperContent.Replace('$IdleTimeoutMinutesPlaceholder', $IdleTimeoutMinutes)
$helperFinal = $helperFinal.Replace('$WebhookUrlPlaceholder', $WebhookUrl)

$helperFinal | Out-File -FilePath $helperPath -Encoding utf8 -Force

# --- Scheduled Task Setup ---
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$helperPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
$trigger.Repetition.Interval = "PT15M"
$trigger.Repetition.Duration = "PT6H"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "SmartAutoShutdown" -Action $action -Trigger $trigger -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force -Settings $settings

Write-Host "Scheduled task 'SmartAutoShutdown' created. Starts at $StartTime and shuts down after $IdleTimeoutMinutes minutes of inactivity."
if (-not [string]::IsNullOrEmpty($WebhookUrl)) {
    Write-Host "A webhook notification will be sent before shutdown."
}

