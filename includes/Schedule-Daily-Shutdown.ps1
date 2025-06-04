# Schedule daily shutdown at 9 PM
$taskName = "Daily Shutdown"

# Remove existing task if it exists
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/s /t 0"
$trigger = New-ScheduledTaskTrigger -Daily -At 21:00
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Shuts down the machine every day at 9 PM" -RunLevel Highest -User "SYSTEM"
