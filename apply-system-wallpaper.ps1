<#
.SYNOPSIS
    Apply a custom wallpaper system-wide.
.DESCRIPTION
    Copies wallpaper\wallpaper.png from the repository to C:\wallpaper\wallpaper.png
    and sets it for all users using the Win32 SystemParametersInfo API. The
    copied image is annotated with the machine name, internal IP and external IP
    before being applied. Registry entries are created under HKLM so that the
    wallpaper persists for new and existing accounts. All output is logged to
    C:\wallpaper\apply_wallpaper.log.
.NOTES
    Requires administrative privileges. Tested on Windows 10 and Windows 11.
#>

#Requires -RunAsAdministrator

param()

# --------------------------------------------------------------------------------
# Helper Functions
# --------------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $LogFile -Value ("$(Get-Date -Format 'u') : $Message")
}

# Return the first non-loopback IPv4 address on the system
function Get-InternalIP {
    try {
        $addr = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike '169.254*' } |
                Select-Object -First 1 -ExpandProperty IPAddress
        if (-not $addr) {
            $addr = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1 -ExpandProperty IPAddress)
        }
        return $addr
    } catch {
        Write-Log "Failed to obtain internal IP: $_"
        return 'Unknown'
    }
}

# Query an external service to determine public IP
function Get-ExternalIP {
    try {
        return (Invoke-RestMethod -Uri 'https://api.ipify.org')
    } catch {
        Write-Log "Failed to obtain external IP: $_"
        return 'Unknown'
    }
}

# Overlay text onto an image in-place
function Add-WallpaperOverlay {
    param(
        [string]$ImagePath,
        [string]$Text
    )
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($ImagePath)
        $gfx = [System.Drawing.Graphics]::FromImage($img)
        $font = New-Object System.Drawing.Font('Arial', 24, [System.Drawing.FontStyle]::Bold)
        $rect = New-Object System.Drawing.RectangleF(10, $img.Height - 110, $img.Width - 20, 100)
        $bgBrush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(128,0,0,0))
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $gfx.FillRectangle($bgBrush, $rect)
        $gfx.DrawString($Text, $font, $textBrush, $rect)
        $img.Save($ImagePath)
        $gfx.Dispose(); $img.Dispose()
        Write-Log "Added overlay information to wallpaper"
    } catch {
        Write-Log "Failed to add overlay: $_"
    }
}

function Set-WallpaperRegistry {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name Wallpaper -Value $WallpaperPath -Type String -Force
        Set-ItemProperty -Path $Path -Name WallpaperStyle -Value '10' -Type String -Force
        Set-ItemProperty -Path $Path -Name TileWallpaper -Value '0' -Type String -Force
        Write-Log "Set registry values at $Path"
    } catch {
        Write-Log "Failed to set registry values at $Path : $_"
    }
}

# --------------------------------------------------------------------------------
# Determine paths
# --------------------------------------------------------------------------------
$ScriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoWallpaper = Join-Path $ScriptRoot 'wallpaper\wallpaper.png'
$WallpaperDir  = 'C:\wallpaper'
$WallpaperPath = Join-Path $WallpaperDir 'wallpaper.png'
$LogFile       = Join-Path $WallpaperDir 'apply_wallpaper.log'

# Create wallpaper directory and log file
if (-not (Test-Path $WallpaperDir)) {
    New-Item -Path $WallpaperDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogFile)) { New-Item -Path $LogFile -ItemType File -Force | Out-Null }

# --------------------------------------------------------------------------------
# Start logging
# --------------------------------------------------------------------------------
Write-Log "Starting wallpaper application" 

# Copy wallpaper from repository
try {
    Copy-Item -Path $RepoWallpaper -Destination $WallpaperPath -Force
    Write-Log "Copied $RepoWallpaper to $WallpaperPath"
} catch {
    Write-Log "Failed to copy wallpaper: $_"
    exit 1
}

# --------------------------------------------------------------------------
# Add overlay information to the wallpaper copy
# --------------------------------------------------------------------------
$machine   = $env:COMPUTERNAME
$internal  = Get-InternalIP
$external  = Get-ExternalIP
$overlay   = "Machine: $machine`nInternal IP: $internal`nExternal IP: $external"
Add-WallpaperOverlay -ImagePath $WallpaperPath -Text $overlay

# --------------------------------------------------------------------------------
# Load SystemParametersInfo from user32.dll
# --------------------------------------------------------------------------------
Add-Type @" 
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool SystemParametersInfo(int action, int uParam, string vParam, int winIni);
}
"@

# Apply for current session
try {
    [NativeMethods]::SystemParametersInfo(20, 0, $WallpaperPath, 1 -bor 2) | Out-Null
    Write-Log "Applied wallpaper to current session"
} catch {
    Write-Log "SystemParametersInfo failed: $_"
}

# --------------------------------------------------------------------------------
# Registry changes for persistence
# --------------------------------------------------------------------------------
# Policy key so new users inherit the wallpaper
$PolicyKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
Set-WallpaperRegistry $PolicyKey

# Logon screen / SYSTEM account
Set-WallpaperRegistry 'HKU:\.DEFAULT\Control Panel\Desktop'

# Current user
Set-WallpaperRegistry 'HKCU:\Control Panel\Desktop'

# Already loaded user profiles
Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.Name -match 'S-1-5-21-' } | ForEach-Object {
    Set-WallpaperRegistry "Registry::$($_.Name)\Control Panel\Desktop"
}

# Offline profiles in C:\Users
Get-ChildItem 'C:\Users' -Directory | Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') } | ForEach-Object {
    $ntUser = Join-Path $_.FullName 'NTUSER.DAT'
    if (Test-Path $ntUser) {
        $hive = "TempHive_$($_.Name)"
        reg.exe load "HKU\$hive" $ntUser > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            try {
                Set-WallpaperRegistry "Registry::HKEY_USERS\$hive\Control Panel\Desktop"
            } finally {
                reg.exe unload "HKU\$hive" > $null 2>&1
            }
        } else {
            Write-Log "Failed to load hive for $($_.Name)"
        }
    }
}

Write-Log "Wallpaper applied for all profiles"
Write-Log "Script complete"
