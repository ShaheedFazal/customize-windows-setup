# Applies a Harden System Security report (HotCakeX/Harden-Windows-Security)
# as the very first customization step. Designed to run on a schedule.
#
# Documented mechanism (see HSS wiki):
#   HSS.exe --cli ImportReport --in=<file> --mode=full
#   "Import and apply a previously exported system state report. Elevation
#    is required. full -> apply all measures marked applied AND remove all
#    measures marked not applied."
#
# Execution context:
#   - Safe to run as SYSTEM (SuperOps default) OR as an interactive admin.
#   - HSS.exe is a Microsoft Store app. PATH/AppExecutionAlias does NOT resolve
#     under SYSTEM, so we locate HSS.exe via Get-AppxPackage -AllUsers.
#   - Installation: winget `--source msstore` is unreliable under SYSTEM.
#     This script will only attempt winget when run interactively. Under SYSTEM
#     the app must be pre-installed (Store, or one-off user-context winget).
#
# Re-run policy:
#   SHA-256 of the report is recorded at
#     HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity\ReportHash
#   Same hash -> skip. Different/missing -> apply and update. To force a
#   re-apply on the next run, delete that registry value.

$ReportFile = Join-Path $PSScriptRoot 'Harden-System-Security.report.json'
$StateKey   = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$StoreId    = '9p7ggfl7dx57'
$PkgFamily  = 'VioletHansen.HardenSystemSecurity_ea7andspwdn10'
$PkgName    = 'VioletHansen.HardenSystemSecurity'

if (-not (Test-Path -LiteralPath $ReportFile)) {
    Write-Log "ERROR: Harden System Security report not found at $ReportFile"
    Write-Host "[ERROR] Report file missing: $ReportFile" -ForegroundColor Red
    return
}

function Test-IsSystem {
    ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value -eq 'S-1-5-18'
}

function Resolve-HssExe {
    # Look up the installed Appx package across all users, then point at HSS.exe
    # inside its InstallLocation. Works whether we're SYSTEM or an admin user.
    $pkg = Get-AppxPackage -AllUsers -Name $PkgName -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if (-not $pkg) { return $null }
    $exe = Join-Path $pkg.InstallLocation 'HSS.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    return $null
}

function Install-Hss {
    if (Test-IsSystem) {
        throw @"
Harden System Security is not installed and this script is running as SYSTEM.
Microsoft Store installs via winget are unreliable under SYSTEM. Install once
in an interactive admin context with:

    winget install --id $StoreId --exact --source msstore ``
        --accept-package-agreements --accept-source-agreements

or via the Store: https://apps.microsoft.com/detail/$StoreId
Then re-run this script.
"@
    }
    Write-Host '[INFO] Installing Harden System Security from Microsoft Store...' -ForegroundColor Cyan
    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install "App Installer" from the Microsoft Store and re-run.'
    }
    & winget install --id $StoreId --exact `
        --accept-package-agreements --accept-source-agreements `
        --source msstore | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Hss {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$Arguments)
    Write-Host "[INFO] $Exe $($Arguments -join ' ')" -ForegroundColor DarkCyan
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "HSS.exe exited with code $LASTEXITCODE."
    }
}

try {
    $currentHash = (Get-FileHash -LiteralPath $ReportFile -Algorithm SHA256).Hash
    $storedHash  = $null
    if (Test-Path -LiteralPath $StateKey) {
        $storedHash = (Get-ItemProperty -Path $StateKey -Name 'ReportHash' -ErrorAction SilentlyContinue).ReportHash
    }

    if ($storedHash -eq $currentHash) {
        Write-Host "[INFO] Harden System Security report unchanged (hash $($currentHash.Substring(0,12))...); skipping." -ForegroundColor DarkGray
        return
    }

    $hss = Resolve-HssExe
    if (-not $hss) {
        Install-Hss
        $hss = Resolve-HssExe
        if (-not $hss) { throw 'HSS.exe still not found after install attempt.' }
    }
    Write-Host "[INFO] Using HSS.exe at: $hss" -ForegroundColor DarkGray

    Write-Host "[INFO] Importing report '$ReportFile' (mode=full)..." -ForegroundColor Cyan
    Invoke-Hss -Exe $hss -Arguments @('--cli', 'ImportReport', "--in=$ReportFile", '--mode=full')
    Write-Log "Harden System Security: imported report from $ReportFile in mode=full (hash $currentHash)."

    Set-RegistryValue -Path $StateKey -Name 'ReportHash'     -Value $currentHash                               -Type 'String' -Force
    Set-RegistryValue -Path $StateKey -Name 'ReportPath'     -Value $ReportFile                                -Type 'String' -Force
    Set-RegistryValue -Path $StateKey -Name 'LastAppliedUtc' -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String' -Force

    Write-Host '[SUCCESS] Harden System Security report applied.' -ForegroundColor Green
} catch {
    Write-Log "ERROR: Harden System Security apply failed - $_"
    Write-Host "[ERROR] Harden System Security apply failed: $_" -ForegroundColor Red
}
