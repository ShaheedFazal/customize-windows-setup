# Ensure-Apps.ps1
#
# SuperOps-friendly bootstrap. Run as SYSTEM. Idempotent.
#
# - Ensures winget (App Installer MSIX) is provisioned for all users.
# - Installs machine-scope winget apps directly (PowerShell 7, Chrome, Drive).
# - Registers a per-user scheduled task that installs msstore / per-user apps
#   (Harden System Security) at logon and daily, in the user's context where
#   `winget --source msstore` actually works.
# - Registers an admin-elevated scheduled task that applies the HSS report
#   (HardenSystemSecurity.exe needs UAC + interactive desktop, which SYSTEM
#   session 0 can't provide).
# - Writes status flags under HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps for a
#   companion Verify-Apps.ps1 to alert on.
#
# Re-running is safe: every action checks state first and no-ops when done.

[CmdletBinding()]
param(
    [string] $TaskPath        = '\CustomizeWindowsSetup\',
    [string] $InstallTaskName = 'Install-UserApps',
    [string] $ApplyTaskName   = 'Apply-HardenSystemSecurityReport'
)

$ErrorActionPreference = 'Continue'  # never block the rest of the script
$StateRoot = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps'
$LogDir    = 'C:\Temp'
$LogFile   = Join-Path $LogDir 'Ensure-Apps.log'

# --- Machine-scope apps: installed now, as SYSTEM, via winget --------------
$MachineApps = @(
    @{ Key='PowerShell7';  WingetId='Microsoft.PowerShell';  Detect={ Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe' } },
    @{ Key='Chrome';       WingetId='Google.Chrome';         Detect={ Test-Path 'C:\Program Files\Google\Chrome\Application\chrome.exe' } },
    @{ Key='GoogleDrive';  WingetId='Google.GoogleDrive';    Detect={ Test-Path 'C:\Program Files\Google\Drive File Stream\launch.bat' } }
)

# --- User-scope apps: installed by the scheduled task at user logon --------
$UserApps = @(
    @{ Key='HardenSystemSecurity'; WingetId='9p7ggfl7dx57'; Source='msstore'; DetectAppx='VioletHansen.HardenSystemSecurity' }
)

# --- Helpers ---------------------------------------------------------------
function Write-AppLog {
    param([string]$Message)
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Set-AppState {
    param([string]$Key, [string]$Name, $Value, [string]$Type = 'String')
    $path = Join-Path $StateRoot $Key
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Test-IsAdmin {
    $cur = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $cur.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    throw 'Ensure-Apps.ps1 must run as Administrator or SYSTEM.'
}

# --- Step 1: ensure winget (App Installer) is present for all users --------
function Ensure-Winget {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-AppLog 'winget already present.'
        Set-AppState -Key 'Winget' -Name 'Installed' -Value 1 -Type 'DWord'
        return
    }
    # Provisioning the MSIX bundle works under SYSTEM (unlike `winget install`).
    # If App Installer is missing, you typically need to download the bundle —
    # SuperOps users usually keep one cached. We try Get-AppxPackage first in
    # case it's installed but not on SYSTEM's PATH.
    $appx = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
    if ($appx) {
        Write-AppLog "App Installer present (Appx) v$($appx.Version) but not on PATH for SYSTEM. Will be picked up at user logon."
        Set-AppState -Key 'Winget' -Name 'Installed' -Value 1 -Type 'DWord'
        return
    }
    Write-AppLog 'WARNING: winget / App Installer not present. Push your existing Install/Upgrade Winget script first, or pre-provision Microsoft.DesktopAppInstaller MSIX.'
    Set-AppState -Key 'Winget' -Name 'Installed' -Value 0 -Type 'DWord'
}

# --- Step 2: install machine-scope apps directly ---------------------------
function Install-MachineApp {
    param($App)
    if (& $App.Detect) {
        Write-AppLog "$($App.Key) already installed; skipping."
        Set-AppState -Key $App.Key -Name 'Installed' -Value 1 -Type 'DWord'
        return
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-AppLog "$($App.Key) install skipped: winget not on PATH for SYSTEM."
        Set-AppState -Key $App.Key -Name 'Installed' -Value 0 -Type 'DWord'
        return
    }
    Write-AppLog "Installing $($App.Key) ($($App.WingetId)) machine-scope..."
    & winget.exe install --id $App.WingetId --exact --source winget --scope machine `
        --accept-package-agreements --accept-source-agreements --silent *>> $LogFile
    $code = $LASTEXITCODE
    $ok   = (& $App.Detect)
    Set-AppState -Key $App.Key -Name 'Installed'      -Value ([int]$ok)  -Type 'DWord'
    Set-AppState -Key $App.Key -Name 'LastInstallExit' -Value $code      -Type 'DWord'
    Set-AppState -Key $App.Key -Name 'LastAttemptUtc'  -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String'
    Write-AppLog "$($App.Key) winget exit=$code, detected=$ok."
}

# --- Step 3: register per-user logon+daily task for user-scope apps --------
function Register-UserAppsTask {
    # Build a payload that loops over the user-scope app list with retries.
    $items = $UserApps | ForEach-Object {
        $detect = if ($_.DetectAppx) { "Get-AppxPackage -Name '$($_.DetectAppx)' -ErrorAction SilentlyContinue" } else { '$null' }
        "@{ Key='$($_.Key)'; WingetId='$($_.WingetId)'; Source='$($_.Source)'; Detect={ $detect } }"
    }
    $itemBlock = '@(' + ($items -join ', ') + ')'

    $payload = @"
`$ErrorActionPreference = 'Continue'
`$log = 'C:\Temp\Ensure-Apps.log'
`$stateRoot = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps'
function Log(`$m) { Add-Content -Path `$log -Value "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [`$env:USERNAME] `$m" }
function SetState(`$k,`$n,`$v,`$t='String') {
    `$p = Join-Path `$stateRoot `$k
    if (-not (Test-Path `$p)) { New-Item -Path `$p -Force | Out-Null }
    New-ItemProperty -Path `$p -Name `$n -Value `$v -PropertyType `$t -Force | Out-Null
}

`$apps = $itemBlock
foreach (`$app in `$apps) {
    if (& `$app.Detect) {
        Log "`$(`$app.Key) already installed; skipping."
        SetState `$app.Key 'Installed' 1 'DWord'
        continue
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Log "`$(`$app.Key): winget not available."
        SetState `$app.Key 'Installed' 0 'DWord'
        continue
    }
    `$delays = @(0, 60, 300)  # immediate, +1m, +5m
    foreach (`$d in `$delays) {
        if (`$d -gt 0) { Start-Sleep -Seconds `$d }
        Log "`$(`$app.Key): winget install attempt (after `${d}s)..."
        & winget.exe install --id `$app.WingetId --exact --source `$app.Source ``
            --accept-package-agreements --accept-source-agreements --silent *>> `$log
        if (`$LASTEXITCODE -eq 0 -and (& `$app.Detect)) {
            SetState `$app.Key 'Installed' 1 'DWord'
            SetState `$app.Key 'LastInstallExit' 0 'DWord'
            SetState `$app.Key 'LastAttemptUtc' (Get-Date).ToUniversalTime().ToString('o') 'String'
            Log "`$(`$app.Key): install succeeded."
            break
        }
        SetState `$app.Key 'LastInstallExit' `$LASTEXITCODE 'DWord'
        SetState `$app.Key 'LastAttemptUtc' (Get-Date).ToUniversalTime().ToString('o') 'String'
        Log "`$(`$app.Key): attempt failed (exit `$LASTEXITCODE)."
    }
}
"@

    $payloadDir  = Join-Path $env:ProgramData 'CustomizeWindowsSetup'
    if (-not (Test-Path $payloadDir)) { New-Item -Path $payloadDir -ItemType Directory -Force | Out-Null }
    $payloadPath = Join-Path $payloadDir 'Install-UserApps.task.ps1'
    Set-Content -Path $payloadPath -Value $payload -Encoding UTF8 -Force

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$payloadPath`""

    $logon = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay = 'PT2M'
    $daily = New-ScheduledTaskTrigger -Daily -At 3am

    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $InstallTaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $InstallTaskName -Confirm:$false
    }
    Register-ScheduledTask `
        -TaskPath $TaskPath -TaskName $InstallTaskName `
        -Action $action -Trigger @($logon, $daily) `
        -Principal $principal -Settings $settings `
        -Description 'CustomizeWindowsSetup: installs per-user MS Store / msstore-source apps for the logged-in user. Idempotent. Logon + daily 03:00.' | Out-Null

    Write-AppLog "Scheduled task registered: $TaskPath$InstallTaskName (payload: $payloadPath)"
    Set-AppState -Key 'UserAppsTask' -Name 'Registered'  -Value 1                            -Type 'DWord'
    Set-AppState -Key 'UserAppsTask' -Name 'PayloadPath' -Value $payloadPath                 -Type 'String'
    Set-AppState -Key 'UserAppsTask' -Name 'RegisteredUtc' -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String'
}

# --- Step 4: register admin-elevated apply task for HSS report -------------
function Register-ApplyHssTask {
    # Payload script — runs in an admin user's session (NO UAC prompt because
    # task is registered with RunLevel Highest). Reads staged report from
    # ProgramData, hash-checks vs HKLM, applies via HSS.exe if needed, writes
    # detailed status back to HKLM for Verify-Apps to read.
    $payload = @'
$ErrorActionPreference = 'Continue'
$report   = 'C:\ProgramData\CustomizeWindowsSetup\Harden-System-Security.report.json'
$stateKey = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$log      = 'C:\Temp\Apply-HardenSystemSecurityReport.log'
$pkgName  = 'VioletHansen.HardenSystemSecurity'

function Log($m) {
    if (-not (Test-Path 'C:\Temp')) { New-Item 'C:\Temp' -ItemType Directory -Force | Out-Null }
    Add-Content -Path $log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$env:USERNAME] $m"
}
function SetState($name, $value, $type = 'String') {
    if (-not (Test-Path $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
    New-ItemProperty -Path $stateKey -Name $name -Value $value -PropertyType $type -Force | Out-Null
}

Log "Apply task fired."

if (-not (Test-Path -LiteralPath $report)) {
    Log "No staged report at $report; nothing to apply."
    return
}

$currentHash = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
$storedHash  = (Get-ItemProperty -Path $stateKey -Name 'ReportHash' -ErrorAction SilentlyContinue).ReportHash
$storedStat  = (Get-ItemProperty -Path $stateKey -Name 'LastAppliedStatus' -ErrorAction SilentlyContinue).LastAppliedStatus

if ($currentHash -eq $storedHash -and $storedStat -eq 'success') {
    Log "Hash matches ($($currentHash.Substring(0,12))...) and last status is success; skip."
    return
}

$pkg = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pkg) {
    Log "HSS package not installed yet; will retry next trigger."
    SetState 'LastAppliedStatus' 'pending-install'
    SetState 'LastAttemptUtc'    (Get-Date).ToUniversalTime().ToString('o')
    return
}

$exe = $null
foreach ($name in 'HardenSystemSecurity.exe','HSS.exe') {
    $p = Join-Path $pkg.InstallLocation $name
    if (Test-Path -LiteralPath $p) { $exe = $p; break }
}
if (-not $exe) {
    Log "Binary not found in $($pkg.InstallLocation)."
    SetState 'LastAppliedStatus' 'binary-missing'
    SetState 'LastAttemptUtc'    (Get-Date).ToUniversalTime().ToString('o')
    return
}

Log "Applying via $exe (hash $($currentHash.Substring(0,12))..., HSS v$($pkg.Version))."
SetState 'LastAppliedStatus' 'in-progress'
SetState 'LastAttemptUtc'    (Get-Date).ToUniversalTime().ToString('o')

$proc = Start-Process -FilePath $exe `
    -ArgumentList @('--cli','ImportReport',"--in=$report",'--mode=full') `
    -PassThru -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue

if (-not $proc) {
    Log "Start-Process returned null."
    SetState 'LastAppliedStatus'   'launch-failed'
    SetState 'LastAppliedExitCode' -1 'DWord'
    return
}

$exit = $proc.ExitCode
SetState 'LastAppliedExitCode' $exit 'DWord'

if ($exit -eq 0) {
    SetState 'ReportHash'        $currentHash
    SetState 'ReportPath'        $report
    SetState 'LastAppliedUtc'    (Get-Date).ToUniversalTime().ToString('o')
    SetState 'AppliedHssVersion' $pkg.Version.ToString()
    SetState 'LastAppliedStatus' 'success'
    Log "Apply succeeded."
} else {
    SetState 'LastAppliedStatus' 'failed'
    Log "Apply failed (exit $exit)."
}
'@

    $payloadDir  = Join-Path $env:ProgramData 'CustomizeWindowsSetup'
    if (-not (Test-Path $payloadDir)) { New-Item -Path $payloadDir -ItemType Directory -Force | Out-Null }
    $payloadPath = Join-Path $payloadDir 'Apply-HardenSystemSecurityReport.task.ps1'
    Set-Content -Path $payloadPath -Value $payload -Encoding UTF8 -Force

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$payloadPath`""

    # Logon trigger delayed 5 min so the Install-UserApps task (2 min delay)
    # has a chance to install HSS first when both fire from the same logon.
    $logon = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay = 'PT5M'
    # Daily at 04:00 so it lands after the 03:00 install task.
    $daily = New-ScheduledTaskTrigger -Daily -At 4am

    # Principal = local Administrators group, RunLevel Highest.
    # Task fires for any signed-in admin user with full elevation — no UAC.
    $principal = New-ScheduledTaskPrincipal `
        -GroupId 'S-1-5-32-544' `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -Hidden `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $ApplyTaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $ApplyTaskName -Confirm:$false
    }
    Register-ScheduledTask `
        -TaskPath $TaskPath -TaskName $ApplyTaskName `
        -Action $action -Trigger @($logon, $daily) `
        -Principal $principal -Settings $settings `
        -Description 'CustomizeWindowsSetup: applies the staged HSS hardening report via HardenSystemSecurity.exe in an elevated admin user session. Idempotent.' | Out-Null

    Write-AppLog "Scheduled task registered: $TaskPath$ApplyTaskName (payload: $payloadPath)"
    Set-AppState -Key 'ApplyHssTask' -Name 'Registered'    -Value 1                                                -Type 'DWord'
    Set-AppState -Key 'ApplyHssTask' -Name 'PayloadPath'   -Value $payloadPath                                     -Type 'String'
    Set-AppState -Key 'ApplyHssTask' -Name 'RegisteredUtc' -Value (Get-Date).ToUniversalTime().ToString('o')       -Type 'String'
}

# --- Run -------------------------------------------------------------------
Write-AppLog '--- Ensure-Apps.ps1 starting ---'
Ensure-Winget
foreach ($app in $MachineApps) { Install-MachineApp -App $app }
Register-UserAppsTask
Register-ApplyHssTask
Set-AppState -Key 'Bootstrap' -Name 'LastRunUtc' -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String'
Write-AppLog '--- Ensure-Apps.ps1 finished ---'
Write-Host '[SUCCESS] Ensure-Apps complete. See HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps for status.' -ForegroundColor Green
