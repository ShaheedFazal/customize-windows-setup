<#
.SYNOPSIS
Apply user-level customizations using pre-tested scripts.

.DESCRIPTION
Runs a curated set of scripts from the includes directory that modify only
HKCU or user-profile locations. The list is hard coded based on one-time
analysis. Scripts requiring administrator rights are excluded.
#>

# Determine root and includes folder
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$IncludesPath = Join-Path $ScriptRoot 'includes'

# Load shared helper functions if present
$regPath = Join-Path $IncludesPath 'Shared-Functions.ps1'
if (Test-Path $regPath) {
    . $regPath
}

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
$CurrentUser = $env:USERNAME

Write-Host "`n=== User-Level Customizations ===" -ForegroundColor Cyan
Write-Host "User: $CurrentUser" -ForegroundColor Gray
Write-Host "Privileges: $(if($IsAdmin){'Administrator'}else{'Standard User'})" -ForegroundColor $(if($IsAdmin){'Green'}else{'Yellow'})

# List of validated user-level scripts
$userScripts = @(
    @{ Script = 'ZZ-Set-FileAssociations.ps1';      Description = 'Configure file associations' },
    @{ Script = 'Hide-Recently-Shortcuts.ps1';       Description = 'Hide recently used shortcuts' },
    @{ Script = 'Hide-People-Icon-Taskbar.ps1';      Description = 'Hide People icon from taskbar' },
    @{ Script = 'Hide-Task-View-Button.ps1';         Description = 'Hide Task View button' },
    @{ Script = 'Hide-User-Folder-From-Desktop.ps1'; Description = 'Hide User Folder icon from desktop' },
    @{ Script = 'Show-All-Tray-Icons.ps1';           Description = 'Show all system tray icons' },
    @{ Script = 'Show-Small-Icons-in-Taskbar.ps1';   Description = 'Use small taskbar icons' },
    @{ Script = 'Set-Control-Panel-View-to-Small-Icons.ps1'; Description = 'Set Control Panel to small icons' },
    @{ Script = 'ZZZ-Set-Wallpaper.ps1';    Description = 'Set wallpaper' }
)

function Invoke-UserScript {
    param(
        [string]$Name,
        [string]$Description
    )

    $path = Join-Path $IncludesPath $Name
    Write-Host "`n-- $Description --" -ForegroundColor Yellow

    if (!(Test-Path $path)) {
        Write-Host "Script not found: $Name" -ForegroundColor Red
        return $false
    }

    try {
        & $path
        Write-Host "[OK] $Description" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[FAILED] $Description : $_" -ForegroundColor Red
        return $false
    }
}

$results = foreach ($s in $userScripts) {
    $ok = Invoke-UserScript -Name $s.Script -Description $s.Description
    [PSCustomObject]@{ Name = $s.Script; Success = $ok }
}

$success = ($results | Where-Object Success).Count
$total   = $results.Count
Write-Host "`nCompleted $success of $total user customizations." -ForegroundColor $(if($success -eq $total){'Green'}else{'Yellow'})

Read-Host "`nPress Enter to exit..."
