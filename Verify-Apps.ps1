# Verify-Apps.ps1
#
# SuperOps monitor companion to Ensure-Apps.ps1.
# Reads HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps state AND re-checks each
# app's actual presence. Prints one line per check and exits non-zero if
# anything looks wrong — schedule this in SuperOps to get alerts when an
# endpoint drifts.

$ErrorActionPreference = 'Continue'

$Checks = @(
    @{ Key='Winget';               Detect={ [bool](Get-Command winget.exe -ErrorAction SilentlyContinue) -or [bool](Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue) } },
    @{ Key='PowerShell7';          Detect={ Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe' } },
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
$state        = if (Test-Path $hssKey) { Get-ItemProperty -Path $hssKey -ErrorAction SilentlyContinue } else { $null }

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

# Staleness: apply older than 30 days = something's wrong
if ($state -and $state.LastAppliedUtc) {
    try {
        $applied = [DateTime]::Parse($state.LastAppliedUtc).ToUniversalTime()
        $ageDays = (New-TimeSpan -Start $applied -End ([DateTime]::UtcNow)).TotalDays
        if ($ageDays -gt 30) {
            Write-Host "WARN    HSS report stale: applied $([math]::Round($ageDays)) days ago ($($state.LastAppliedUtc))"
            $bad++
        } else {
            Write-Host "INFO    HSS report last applied: $($state.LastAppliedUtc) ($([math]::Round($ageDays,1)) days ago)"
        }
    } catch {
        Write-Host "INFO    HSS report last applied: $($state.LastAppliedUtc) (could not parse)"
    }
}

# Drift: staged report on disk differs from what HKLM says was applied
if (Test-Path -LiteralPath $stagedReport) {
    $stagedHash = (Get-FileHash -LiteralPath $stagedReport -Algorithm SHA256).Hash
    if ($state -and $state.ReportHash) {
        if ($stagedHash -ne $state.ReportHash) {
            Write-Host "WARN    HSS report drift: staged hash $($stagedHash.Substring(0,12))... differs from applied $($state.ReportHash.Substring(0,12))..."
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
