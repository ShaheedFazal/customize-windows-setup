<#
.Synopsis
PowerShell post-installation script to minimize and customize Windows operating systems
 
.Description
This post-installation script minimizes and customizes a Windows client and
applies settings for all existing user profiles and the default template for
new accounts.
 
.Notes
File Name:      customize-windows-client.ps1
Author:         https://github.com/filipnet/customize-windows-client
License:        BSD 3-Clause "New" or "Revised" License
Requires:       PowerShell 5.1 or above + RunAsAdministrator

.Example
.\customize-windows-client.ps1
 
.LINK
https://github.com/filipnet/customize-windows-client
#>

# Parameters
[CmdletBinding()]
param()

# Variables
$DRIVELABELSYS = "OS"
$TEMPFOLDER = "C:\Temp"
$INSTALLFOLDER = "C:\Install"
$POWERMANAGEMENT = "High performance"
$DRIVELETTERCDROM = "z:"
$WINDOWSBUILD = (Get-WmiObject Win32_OperatingSystem).BuildNumber
$WINDOWSSERVER2016 = "14393"
$WINDOWSSERVER2019 = "17763"
$CR = "`n"
$BLANK = " "
$TIME = Get-Date -UFormat "%A %d.%m.%Y %R"
$FOREGROUNDCOLOR = "Yellow"
$OFFICESUITE = "Google"  # Set to 'Google' or 'LibreOffice' to configure defaults

# Determine script and includes directory. The script looks for the 'includes'
# folder relative to its own location.
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$IncludesPath = Join-Path $ScriptRoot 'includes'
# Load shared helper functions for all scripts
. (Join-Path $IncludesPath 'Shared-Functions.ps1')
$templateFunctionsPath = Join-Path $IncludesPath 'Profile-Template-Functions.ps1'
if (Test-Path $templateFunctionsPath) {
    . $templateFunctionsPath
}


# ---------- DO NOT CHANGE THINGS BELOW THIS LINE -----------------------------

# Check if the powershell is started as an administrator
function Test-Administrator {
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}


# Ensure the temp folder exists so a transcript can be written
if(!(Test-Path $TEMPFOLDER)) {
    New-Item -ItemType Directory -Force -Path $TEMPFOLDER | Out-Null
}

if (-not (Test-Administrator)) {
    Write-Host "[INFO] Re-launching with administrative privileges..." -ForegroundColor Yellow
    $quotedArgs = $MyInvocation.UnboundArguments | ForEach-Object { '"' + $_ + '"' } -join ' '
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $quotedArgs" -Verb RunAs
    exit
}

# Start logging the console output
$LogPath = Join-Path $TEMPFOLDER ("customize-windows-client-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogPath | Out-Null
# Track script success and collect error messages
$ScriptSuccess = $true
$ErrorMessages = @()

## Create System Restore Point
Write-Host ($CR + "Create system restore point" + $BLANK + $TIME) -foregroundcolor $FOREGROUNDCOLOR $CR
try {
    # Ensure System Restore is enabled and required services are running
    Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
    foreach ($svc in 'VSS','swprv') {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.StartType -eq 'Disabled') {
                Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            }
            if ($service.Status -ne 'Running') {
                Start-Service -Name $svc -ErrorAction SilentlyContinue
            }
        }
    }
    $srRegPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    # Windows throttles restore-point creation to one per 24h by default. Drop
    # the override to 5 minutes so each customize run normally gets a fresh
    # safety net, but back-to-back reruns within minutes share one (avoids
    # hammering VSS — which can stall Checkpoint-Computer for many minutes
    # if invoked too aggressively).
    if (-not (Test-Path $srRegPath)) { New-Item -Path $srRegPath -Force | Out-Null }
    Set-ItemProperty -Path $srRegPath -Name SystemRestorePointCreationFrequency -Value 5 -Type DWord -Force

    # Skip if a recent restore point already exists (5-min window matches the
    # throttle above). Saves time on repeated runs and avoids stalls.
    $recent = Get-ComputerRestorePoint -ErrorAction SilentlyContinue |
        Sort-Object -Property CreationTime -Descending |
        Select-Object -First 1
    $skipRestore = $false
    if ($recent) {
        $elapsedMin = (New-TimeSpan -Start $recent.CreationTime -End (Get-Date)).TotalMinutes
        if ($elapsedMin -lt 5) {
            Write-Host "[INFO] Restore point already exists from $([math]::Round($elapsedMin,1)) min ago; reusing." -ForegroundColor DarkGray
            $skipRestore = $true
        }
    }

    if (-not $skipRestore) {
        # Run Checkpoint-Computer in a background job with a hard timeout so a
        # stalled VSS doesn't hang the entire customize run (and SuperOps).
        $job = Start-Job -ScriptBlock {
            Checkpoint-Computer -Description 'Before customizations' -RestorePointType MODIFY_SETTINGS
        }
        if (Wait-Job -Job $job -Timeout 90) {
            Receive-Job -Job $job | Out-Null
            Write-Host "[OK] System restore point created" -ForegroundColor Green
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Write-Warning "Checkpoint-Computer did not complete within 90s; continuing without a fresh restore point. Check VSS health on this endpoint."
            $ErrorMessages += 'Restore point: timed out after 90s'
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Failed to create restore point: $_"
    $ScriptSuccess = $false
    $ErrorMessages += "Restore point: $_"
}

# Create C:\Temp and C:\Install folders if not exists
Write-Host ($CR +"Create $TEMPFOLDER and $INSTALLFOLDER folders") -foregroundcolor $FOREGROUNDCOLOR
try {
    if(!(Test-Path $TEMPFOLDER)) {
        New-Item -ItemType Directory -Force -Path $TEMPFOLDER | Out-Null
    }
    if(!(Test-Path $INSTALLFOLDER)) {
        New-Item -ItemType Directory -Force -Path $INSTALLFOLDER | Out-Null
    }
    # Clear per-run sentinel files used by machine-wide includes to avoid
    # repeating themselves once per user-hive iteration. They're recreated
    # by the relevant scripts the first time they run this session.
    Get-ChildItem -Path $TEMPFOLDER -Filter '*.session' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Failed to create folders: $_"
    $ScriptSuccess = $false
    $ErrorMessages += "Folders: $_"
}

# Backup Registry
Write-Host ($CR +"Create Registry Backup" + $BLANK + $TIME) -foregroundcolor $FOREGROUNDCOLOR $CR

# Backup core hives
$regBackupFiles = @{
    HKLM = "$INSTALLFOLDER\registry-backup-hklm.reg"
    HKCR = "$INSTALLFOLDER\registry-backup-hkcr.reg"
}
foreach ($hive in $regBackupFiles.Keys) {
    $file = $regBackupFiles[$hive]
    try {
        # Suppress reg.exe's noisy stdout/stderr; we report success/failure ourselves.
        $regOutput = reg.exe export $hive $file /y 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file) -or (Get-Item $file).Length -eq 0) {
            throw "reg.exe exit=$LASTEXITCODE output=$regOutput"
        }
        Write-Host "[OK] Backed up $hive -> $file" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to backup registry hive ${hive}: $_"
        $ScriptSuccess = $false
        $ErrorMessages += "Registry backup ${hive}: $_"
    }
}

# Backup all loaded user hives (excluding system accounts)
$defaultHiveKey = 'HKU\DefaultUser'
$defaultProfilePath = Join-Path $env:SystemDrive 'Users\\Default\\NTUSER.DAT'
$defaultHiveLoaded = $false
if (-not (Test-Path "Registry::$defaultHiveKey") -and (Test-Path $defaultProfilePath)) {
    try {
        reg.exe load $defaultHiveKey $defaultProfilePath | Out-Null
        if ($LASTEXITCODE -eq 0) { $defaultHiveLoaded = $true }
    } catch {
        Write-Warning "Failed to load default user hive for backup: $_"
    }
}

$hkuBackupDir = Join-Path $INSTALLFOLDER 'registry-backup-hku'
if (!(Test-Path $hkuBackupDir)) { New-Item -ItemType Directory -Path $hkuBackupDir -Force | Out-Null }
$userHives = Get-ChildItem Registry::HKEY_USERS | Where-Object {
    $_.PSChildName -notmatch '_Classes$' -and
    $_.PSChildName -ne '.DEFAULT' -and
    $_.PSChildName -notmatch '^S-1-5-(18|19|20)$'
}
foreach ($hive in $userHives) {
    $sid = $hive.PSChildName
    $file = Join-Path $hkuBackupDir ("registry-backup-hku-$sid.reg")
    try {
        $regOutput = reg.exe export "HKU\$sid" $file /y 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file) -or (Get-Item $file).Length -eq 0) {
            throw "reg.exe exit=$LASTEXITCODE output=$regOutput"
        }
        Write-Host "[OK] Backed up HKU\$sid" -ForegroundColor Green
    } catch {
        # Some loaded hives (system-protected SIDs like DefaultUser overlays) deny read access.
        # Log a warning but don't mark the whole script as failed — these aren't critical.
        Write-Warning "Skipped HKU\${sid} backup: $_"
    }
}

if ($defaultHiveLoaded) {
    try { reg.exe unload $defaultHiveKey | Out-Null } catch { Write-Warning "Failed to unload default user hive: $_" }
}
# Start customization
Write-Host ($CR +"This system will customized and minimized") -foregroundcolor $FOREGROUNDCOLOR $CR

# Create list of all PowerShell scripts in the includes folder
# Only ".ps1" files should be executed. Other file types like xml
# or documentation files are ignored to prevent errors when invoking them.
$AllActions = Get-ChildItem -Path $IncludesPath -Filter '*.ps1' -File |
    Sort-Object -Property Name

function Invoke-Customizations {
    param([string]$UserLabel)

    # Files prefixed with ZZZ should run after default profile templating
    $PreTemplateActions = $AllActions | Where-Object { $_.Name -notlike 'ZZZ-*' }
    foreach ($Action in $PreTemplateActions) {
        Write-Host "Execute " -NoNewline
        Write-Host ($Action.Name) -ForegroundColor Yellow -NoNewline
        Write-Host " ..."
        try {
            & $Action.FullName
        } catch {
            Write-Warning "Action $($Action.Name) failed: $_"
            $ScriptSuccess = $false
            $ErrorMessages += "$($Action.Name): $_"
        }
    }
    Write-Host ($CR +"All customizations completed for $UserLabel") -foregroundcolor $FOREGROUNDCOLOR
    # Skip profile templating as this functionality is currently disabled

    # Execute actions that should run after default profile templating
    $PostTemplateActions = $AllActions | Where-Object { $_.Name -like 'ZZZ-*' }
    foreach ($Action in $PostTemplateActions) {
        Write-Host "Execute " -NoNewline
        Write-Host ($Action.Name) -ForegroundColor Yellow -NoNewline
        Write-Host " ..."
        try {
            & $Action.FullName
        } catch {
            Write-Warning "Action $($Action.Name) failed: $_"
            $ScriptSuccess = $false
            $ErrorMessages += "$($Action.Name): $_"
        }
    }
}

# Run customizations for the current user (system-wide changes run here as well)
Invoke-Customizations -UserLabel 'current user'

# Process all other loaded user profiles and the default profile for new accounts
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$defaultHiveKey = 'HKU\DefaultUser'
$defaultProfilePath = Join-Path $env:SystemDrive 'Users\\Default\\NTUSER.DAT'
$defaultHiveLoaded = $false
if (-not (Test-Path "Registry::$defaultHiveKey") -and (Test-Path $defaultProfilePath)) {
    try {
        reg.exe load $defaultHiveKey $defaultProfilePath | Out-Null
        if ($LASTEXITCODE -eq 0) { $defaultHiveLoaded = $true }
    } catch {
        Write-Warning "Failed to load default user hive: $_"
    }
}

$userHives = Get-ChildItem Registry::HKEY_USERS | Where-Object {
    $_.PSChildName -notmatch '_Classes$' -and
    $_.PSChildName -ne '.DEFAULT' -and
    $_.PSChildName -notmatch '^S-1-5-(18|19|20)$' -and
    $_.PSChildName -ne $currentSid
}
foreach ($hive in $userHives) {
    $sid = $hive.PSChildName
    Write-Host ($CR +"Applying user-level customizations for hive $sid") -ForegroundColor $FOREGROUNDCOLOR
    try {
        Remove-PSDrive -Name HKCU -Force
        New-PSDrive -Name HKCU -PSProvider Registry -Root $hive.Name | Out-Null
        $profilePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $profilePath -and $sid -eq 'DefaultUser') {
            $profilePath = Join-Path $env:SystemDrive 'Users\\Default'
        }
        $oldProfile = $env:USERPROFILE
        if ($profilePath) { $env:USERPROFILE = $profilePath }
        Invoke-Customizations -UserLabel $sid
        if ($profilePath) { $env:USERPROFILE = $oldProfile }
    } finally {
        Remove-PSDrive -Name HKCU -Force
        New-PSDrive -Name HKCU -PSProvider Registry -Root 'HKEY_CURRENT_USER' | Out-Null
    }
}
if ($defaultHiveLoaded) {
    try { reg.exe unload $defaultHiveKey | Out-Null } catch { Write-Warning "Failed to unload default user hive: $_" }
}
if ($ErrorMessages.Count -eq 0) {
    Write-Host ($CR +"All customizations have been applied successfully") -foregroundcolor $FOREGROUNDCOLOR $CR
    $ExitCode = 0
} else {
    Write-Host ($CR +"Customizations completed with errors:") -ForegroundColor Yellow
    $ErrorMessages | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    $ExitCode = 1
}
Stop-Transcript | Out-Null
exit $ExitCode
