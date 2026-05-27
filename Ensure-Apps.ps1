# Ensure-Apps.ps1
#
# SuperOps-friendly bootstrap. Run as SYSTEM. Idempotent.
#
# - Ensures winget (App Installer MSIX) is provisioned for all users.
# - Installs machine-scope winget apps directly (PowerShell 7, Chrome, Drive).
# - Registers a per-user scheduled task that installs msstore / per-user apps
#   (Harden System Security) at logon and daily, in the user's context where
#   `winget --source msstore` actually works.
# - Writes status flags under HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps for a
#   companion Verify-Apps.ps1 to alert on.
#
# Re-running is safe: every action checks state first and no-ops when done.

[CmdletBinding()]
param(
    [string] $TaskPath = '\CustomizeWindowsSetup\',
    [string] $TaskName = 'Install-UserApps'
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

    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false
    }
    Register-ScheduledTask `
        -TaskPath $TaskPath -TaskName $TaskName `
        -Action $action -Trigger @($logon, $daily) `
        -Principal $principal -Settings $settings `
        -Description 'CustomizeWindowsSetup: installs per-user MS Store / msstore-source apps for the logged-in user. Idempotent. Logon + daily 03:00.' | Out-Null

    Write-AppLog "Scheduled task registered: $TaskPath$TaskName (payload: $payloadPath)"
    Set-AppState -Key 'UserAppsTask' -Name 'Registered'  -Value 1                            -Type 'DWord'
    Set-AppState -Key 'UserAppsTask' -Name 'PayloadPath' -Value $payloadPath                 -Type 'String'
    Set-AppState -Key 'UserAppsTask' -Name 'RegisteredUtc' -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String'
}

# --- Run -------------------------------------------------------------------
Write-AppLog '--- Ensure-Apps.ps1 starting ---'
Ensure-Winget
foreach ($app in $MachineApps) { Install-MachineApp -App $app }
Register-UserAppsTask
Set-AppState -Key 'Bootstrap' -Name 'LastRunUtc' -Value (Get-Date).ToUniversalTime().ToString('o') -Type 'String'
Write-AppLog '--- Ensure-Apps.ps1 finished ---'
Write-Host '[SUCCESS] Ensure-Apps complete. See HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps for status.' -ForegroundColor Green
