# Verify-Apps.ps1
#
# SuperOps monitor companion to Ensure-Apps.ps1.
# Reads HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps status flags AND re-checks
# each app's actual presence. Prints a one-line status per app and exits
# non-zero if anything is missing — schedule this in SuperOps to get alerts
# when an endpoint drifts.

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

# Bonus: surface HSS report state from AA-Apply-HardenSystemSecurity.ps1.
$hssKey = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
if (Test-Path $hssKey) {
    $applied = (Get-ItemProperty -Path $hssKey -ErrorAction SilentlyContinue).LastAppliedUtc
    Write-Host "INFO    HSS report last applied: $applied"
} else {
    Write-Host 'INFO    HSS report has never been applied.'
}

if ($bad -gt 0) {
    Write-Host "[FAIL] $bad item(s) missing." -ForegroundColor Red
    exit 1
}
Write-Host '[OK] All apps present.' -ForegroundColor Green
exit 0
