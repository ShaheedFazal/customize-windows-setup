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

# Determine script and includes directory. The script looks for the 'includes'
# folder relative to its own location.
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$IncludesPath = Join-Path $ScriptRoot 'includes'

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

if(-not (Test-Administrator)) {
    Write-Error "This script must be executed as Administrator.";
    Read-Host “Press ENTER to continue...”
    exit 1;
}

## Create System Restore Point
Write-Host ($CR + "Create system restore point" + $BLANK + $TIME) -foregroundcolor $FOREGROUNDCOLOR $CR
try {
    Checkpoint-Computer -Description "Before customizations" -RestorePointType MODIFY_SETTINGS | Out-Null
} catch {
    Write-Warning "Failed to create restore point: $_"
}

# Create C:\Temp and C:\Install folders if not exists
Write-Host ($CR +"Create $TEMPFOLDER and $INSTALLFOLDER folders") -foregroundcolor $FOREGROUNDCOLOR
If(!(test-path $TEMPFOLDER)) {
    New-Item -ItemType Directory -Force -Path $TEMPFOLDER
}
If(!(test-path $INSTALLFOLDER)) {
    New-Item -ItemType Directory -Force -Path $INSTALLFOLDER
}

## Backup Registry
Write-Host ($CR +"Create Registry Backup" + $BLANK + $TIME) -foregroundcolor $FOREGROUNDCOLOR $CR
reg export HKLM C:\Install\registry-backup-hklm.reg /y | Out-Null
reg export HKCU C:\Install\registry-backup-hkcu.reg /y | Out-Null
reg export HKCR C:\Install\registry-backup-hkcr.reg /y | Out-Null

# Start customization
Write-Host ($CR +"This system will customized and minimized") -foregroundcolor $FOREGROUNDCOLOR $CR
$confirmation = Read-Host "Are you sure you want to proceed? [press: y]"
if ($confirmation -eq 'y') {
    # Create array of actions out of include folder
    $Actions = Get-ChildItem -Path $IncludesPath -File | Select-Object -ExpandProperty Name


    # Execute selected actions"
    foreach ($Action in $Actions) {	
        Write-Host "Execute " -NoNewline
        Write-Host ("$Action") -foregroundcolor Yellow -NoNewline
        Write-Host " ..."
        & (Join-Path $IncludesPath $Action)
    }
}



# Restart to apply all changes
Write-Host ($CR +"This system will restart to apply all changes") -foregroundcolor $FOREGROUNDCOLOR $CR 
$confirmation = Read-Host "Are you sure you want to proceed restart? [press: y]"
if ($confirmation -eq 'y') {
    Restart-Computer -ComputerName localhost
}