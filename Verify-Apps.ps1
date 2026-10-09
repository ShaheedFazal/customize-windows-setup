# Verify-Apps.ps1
#
# SuperOps monitor companion to Ensure-Apps.ps1.
# Reads HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps state AND re-checks each
# app's actual presence. Prints one line per check and exits non-zero if
# anything looks wrong - schedule this in SuperOps to get alerts when an
# endpoint drifts.

$ErrorActionPreference = 'Continue'

$Checks = @(
    @{ Key='Winget';               Detect={ [bool](Get-Command winget.exe -ErrorAction SilentlyContinue) -or [bool](Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue) } },
    @{ Key='PowerShell7';          Detect={ (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') -or [bool](Get-AppxPackage -AllUsers -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue) } },
    @{ Key='Chrome';               Detect={ Test-Path 'C:\Program Files\Google\Chrome\Application\chrome.exe' } },
    @{ Key='GoogleDrive';          Detect={ Test-Path 'C:\Program Files\Google\Drive File Stream\launch.bat' } },
    @{ Key='HardenSystemSecurity'; Detect={ [bool](Get-AppxPackage -AllUsers -Name 'VioletHansen.HardenSystemSecurity' -ErrorAction SilentlyContinue) } }
)

$bad = 0
foreach ($c in $Checks) {
    $present = [bool](& $c.Detect)
    $status  = if ($present) { 'OK     ' } else { 'MISSING' }
    Write-Host "$status $($c.Key)"
    if (-not $present) { $bad++ }
}

# --- HSS hardening health -------------------------------------------------
# Three dimensions: status, staleness, drift.

$hssKey       = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$stagedReport = 'C:\ProgramData\CustomizeWindowsSetup\Harden-System-Security.report.json'
$applyTaskPath = '\CustomizeWindowsSetup\'
$applyTaskName = 'Apply-HardenSystemSecurityReport'
$applyLog      = 'C:\Temp\Apply-HardenSystemSecurityReport.log'
$state        = if (Test-Path $hssKey) { Get-ItemProperty -Path $hssKey -ErrorAction SilentlyContinue } else { $null }

function Write-HssApplyTaskInfo {
    try {
        $task = Get-ScheduledTask -TaskPath $applyTaskPath -TaskName $applyTaskName -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        Write-Host ("INFO    HSS apply task: State={0}, LastRun={1}, LastResult={2}" -f $task.State, $info.LastRunTime, $info.LastTaskResult)
        foreach ($action in @($task.Actions)) {
            Write-Host ("INFO    HSS apply task action: {0} {1}" -f $action.Execute, $action.Arguments)
        }
    } catch {
        Write-Host "WARN    HSS apply task: $applyTaskPath$applyTaskName not registered"
    }
    if ($state -and $state.LastAttemptUtc) {
        Write-Host "INFO    HSS apply last attempt: $($state.LastAttemptUtc)"
    }
    if (Test-Path -LiteralPath $applyLog) {
        try {
            $logItem = Get-Item -LiteralPath $applyLog -ErrorAction Stop
            Write-Host "INFO    HSS apply log: $applyLog ($($logItem.Length) bytes, modified $($logItem.LastWriteTime))"
        } catch {
            Write-Host "INFO    HSS apply log: $applyLog"
        }
    } else {
        Write-Host "WARN    HSS apply log missing: $applyLog"
    }
}

if (-not $state -or -not $state.LastAppliedStatus) {
    Write-Host 'WARN    HSS report: never applied'
    $bad++
} else {
    switch ($state.LastAppliedStatus) {
        'success' {
            Write-Host "OK      HSS apply status: success (exit $($state.LastAppliedExitCode), HSS v$($state.AppliedHssVersion))"
        }
        'pending-install' {
            Write-Host "WARN    HSS apply status: waiting for HSS package to install"
            $bad++
        }
        default {
            Write-Host "FAIL    HSS apply status: $($state.LastAppliedStatus) (last exit $($state.LastAppliedExitCode))"
            $bad++
        }
    }
}

# Staleness: the apply task skips ImportReport while the report is unchanged,
# so an old LastAppliedUtc is normal. What matters is that the task still
# fires; it stamps LastCheckedUtc on every run, including the no-op path.
if ($state -and $state.LastAppliedUtc) {
    Write-Host "INFO    HSS report last applied: $($state.LastAppliedUtc)"
}
if ($state -and $state.LastCheckedUtc) {
    try {
        $checked = [DateTime]::Parse($state.LastCheckedUtc).ToUniversalTime()
        $ageDays = (New-TimeSpan -Start $checked -End ([DateTime]::UtcNow)).TotalDays
        if ($ageDays -gt 14) {
            Write-Host "WARN    HSS apply task stale: last ran $([math]::Round($ageDays)) days ago ($($state.LastCheckedUtc))"
            Write-HssApplyTaskInfo
            $bad++
        } else {
            Write-Host "INFO    HSS apply task last ran: $($state.LastCheckedUtc) ($([math]::Round($ageDays,1)) days ago)"
        }
    } catch {
        Write-Host "INFO    HSS apply task last ran: $($state.LastCheckedUtc) (could not parse)"
    }
}

# Controlled Folder Access must be in Audit (2). Block (1) silently rolls back
# line-of-business installers such as Titan's IDAutomation barcode UFL.
$cfa = (Get-MpPreference -ErrorAction SilentlyContinue).EnableControlledFolderAccess
switch ("$cfa") {
    '2'     { Write-Host 'OK      Controlled Folder Access: Audit' }
    '1'     { Write-Host 'WARN    Controlled Folder Access: Block (expected Audit; apply task override not run yet?)'; $bad++ }
    '0'     { Write-Host 'WARN    Controlled Folder Access: Disabled (expected Audit)'; $bad++ }
    default { Write-Host "INFO    Controlled Folder Access: $cfa" }
}

# Drift: staged report on disk differs from what HKLM says was applied
if (Test-Path -LiteralPath $stagedReport) {
    $stagedHash = (Get-FileHash -LiteralPath $stagedReport -Algorithm SHA256).Hash
    if ($state -and $state.ReportHash) {
        if ($stagedHash -ne $state.ReportHash) {
            Write-Host "WARN    HSS report drift: staged hash $($stagedHash.Substring(0,12))... differs from applied $($state.ReportHash.Substring(0,12))..."
            Write-HssApplyTaskInfo
            $bad++
        }
    }
}

if ($bad -gt 0) {
    Write-Host "[FAIL] $bad issue(s)." -ForegroundColor Red
    exit 1
}
Write-Host '[OK] All checks pass.' -ForegroundColor Green
exit 0
