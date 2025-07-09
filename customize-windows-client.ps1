<#
.Synopsis
PowerShell post-installation script to minimize and customize Windows operating systems
 
.Description
This post-installation script is for minimize and customize a Windows Client.
 
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
    Checkpoint-Computer -Description "Before customizations" -RestorePointType MODIFY_SETTINGS | Out-Null
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
} catch {
    Write-Warning "Failed to create folders: $_"
    $ScriptSuccess = $false
    $ErrorMessages += "Folders: $_"
}

# Backup Registry
Write-Host ($CR +"Create Registry Backup" + $BLANK + $TIME) -foregroundcolor $FOREGROUNDCOLOR $CR
$regBackupFiles = @{ 
    HKLM = "$INSTALLFOLDER\registry-backup-hklm.reg" 
    HKCU = "$INSTALLFOLDER\registry-backup-hkcu.reg" 
    HKCR = "$INSTALLFOLDER\registry-backup-hkcr.reg" 
}
foreach ($hive in $regBackupFiles.Keys) {
    $file = $regBackupFiles[$hive]
    try {
        reg export $hive $file /y
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file) -or (Get-Item $file).Length -eq 0) {
            throw "Registry export for $hive failed"
        }
    } catch {
        Write-Warning "Failed to backup registry hive ${hive}: $_"
        $ScriptSuccess = $false
        $ErrorMessages += "Registry backup ${hive}: $_"
    }
}
# Start customization
Write-Host ($CR +"This system will customized and minimized") -foregroundcolor $FOREGROUNDCOLOR $CR

# Create list of all PowerShell scripts in the includes folder
# Only ".ps1" files should be executed. Other file types like xml
# or documentation files are ignored to prevent errors when invoking them.
$AllActions = Get-ChildItem -Path $IncludesPath -Filter '*.ps1' -File |
    Sort-Object -Property Name

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
Write-Host ($CR +"All customizations completed for current user") -foregroundcolor $FOREGROUNDCOLOR
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
