# Stages the Harden System Security report and triggers the per-user apply
# task. This file runs under SYSTEM (session 0) where HSS.exe CANNOT run —
# the packaged WinUI app needs an interactive desktop + UAC elevation, and
# session 0 has neither. So instead we:
#
#   1. Copy the bundled report into C:\ProgramData\CustomizeWindowsSetup\
#      where the task (running in an admin user's session) can read it.
#   2. Start the scheduled task `\CustomizeWindowsSetup\Apply-HardenSystemSecurityReport`
#      (registered by Ensure-Apps.ps1) which actually invokes HSS.exe with
#      ImportReport. If an admin is logged in, it runs immediately; if not,
#      it's queued for the next logon trigger.
#
# The task does its own hash check against
#   HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity\ReportHash
# so re-staging the same report is a sub-second no-op.

if (Test-MachineWideSentinel -Name 'AA-Apply-HardenSystemSecurity') { return }

$SourceReport = Join-Path $PSScriptRoot 'Harden-System-Security.report.json'
$StageDir     = Join-Path $env:ProgramData 'CustomizeWindowsSetup'
$StagedReport = Join-Path $StageDir 'Harden-System-Security.report.json'
$TaskPath     = '\CustomizeWindowsSetup\'
$TaskName     = 'Apply-HardenSystemSecurityReport'

if (-not (Test-Path -LiteralPath $SourceReport)) {
    Write-Log "ERROR: Harden System Security report not found at $SourceReport"
    Write-Host "[ERROR] Report file missing: $SourceReport" -ForegroundColor Red
    return
}

try {
    if (-not (Test-Path -LiteralPath $StageDir)) {
        New-Item -Path $StageDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $SourceReport -Destination $StagedReport -Force
    Write-Host "[INFO] Staged HSS report at $StagedReport" -ForegroundColor DarkGray
    Write-Log "Staged HSS report at $StagedReport for the apply task."
} catch {
    Write-Log "ERROR: Failed to stage HSS report - $_"
    Write-Host "[ERROR] Failed to stage HSS report: $_" -ForegroundColor Red
    return
}

$task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "[WARN] Scheduled task $TaskPath$TaskName not registered. Run Ensure-Apps.ps1 first." -ForegroundColor Yellow
    Write-Log "Apply task not registered; cannot trigger HSS apply."
    return
}

try {
    Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    Write-Host "[OK] Triggered $TaskPath$TaskName — apply will run in the next admin user session." -ForegroundColor Green
    Write-Log "Triggered $TaskPath$TaskName."
} catch {
    Write-Log "ERROR: Failed to trigger $TaskPath$TaskName - $_"
    Write-Host "[ERROR] Failed to trigger apply task: $_" -ForegroundColor Red
}
