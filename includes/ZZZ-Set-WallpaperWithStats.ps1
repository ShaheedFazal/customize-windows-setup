# Simple Wallpaper Persistence Fix Script
# Standalone script to fix wallpaper persistence issues

#Requires -RunAsAdministrator

param(
    [string]$WallpaperPath = "",
    [switch]$UseSystemDefault
)

# Determine script location and default wallpaper
$ScriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoWallpaper = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'
$SystemDir     = 'C:\\Wallpaper'
$SystemWallpaper = Join-Path $SystemDir 'wallpaper.png'
$LogFile        = Join-Path $SystemDir 'apply_wallpaper.log'

if (-not (Test-Path $SystemDir)) {
    New-Item -Path $SystemDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogFile)) { New-Item -Path $LogFile -ItemType File -Force | Out-Null }

function Write-Log {
    param(
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $LogFile -Value "$(Get-Date -Format 'u') : $Message"
}

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

function Get-ExternalIP {
    try {
        return (Invoke-RestMethod -Uri 'https://api.ipify.org')
    } catch {
        Write-Log "Failed to obtain external IP: $_"
        return 'Unknown'
    }
}

function Add-WallpaperOverlay {
    param(
        [string]$ImagePath,
        [string]$Text
    )
    try {
        $resolved = Resolve-Path -Path $ImagePath -ErrorAction Stop
        $realPath = $resolved[0].ProviderPath

        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($realPath)
        $gfx = [System.Drawing.Graphics]::FromImage($img)
        $font = New-Object System.Drawing.Font('Arial', 24, [System.Drawing.FontStyle]::Bold)
        $rect = New-Object System.Drawing.RectangleF(10, $img.Height - 110, $img.Width - 20, 100)
        $bgBrush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(128,0,0,0))
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $gfx.FillRectangle($bgBrush, $rect)
        $gfx.DrawString($Text, $font, $textBrush, $rect)
        $img.Save($realPath)
        $gfx.Dispose(); $img.Dispose()
        Write-Log "Added overlay information to wallpaper"
    } catch {
        Write-Log "Failed to add overlay: $_"
    }
}

# If no path specified and not forcing system defaults, use repository wallpaper
if ([string]::IsNullOrEmpty($WallpaperPath) -and -not $UseSystemDefault) {
    if (Test-Path $RepoWallpaper) {
        $WallpaperPath = $RepoWallpaper
    }
}

Write-Log "=== WALLPAPER PERSISTENCE FIX ===" -Color Cyan

# Simple registry function (doesn't require shared functions)
function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Type
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Log "[OK] Set $Name in $Path" -Color Green
        return $true
    } catch {
        Write-Log "[FAIL] Failed to set $Name in $Path : $_" -Color Red
        return $false
    }
}

# Attempt to load a registry hive with retries when the file is locked
function Load-RegistryHive {
    param(
        [Parameter(Mandatory)][string]$HivePath,
        [Parameter(Mandatory)][string]$HiveName,
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 5
    )

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $result = & reg.exe load "HKU\$HiveName" $HivePath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Loaded hive $HiveName" -Color Gray
            return $true
        }

        if ($result -match 'used by another process') {
            Write-Log "Hive $HiveName in use. Waiting ($i/$MaxAttempts)..." -Color Yellow
            Start-Sleep -Seconds $DelaySeconds
        } else {
            Write-Log "! Could not load hive ${HiveName}: ${result}" -Color Yellow
            return $false
        }
    }

    Write-Log "! Hive $HiveName still locked after $MaxAttempts attempts" -Color Yellow
    return $false
}

# Determine wallpaper to use
if ($UseSystemDefault -or [string]::IsNullOrEmpty($WallpaperPath)) {
    # Use Windows default wallpapers
    $defaultWallpapers = @(
        "C:\Windows\Web\Wallpaper\Windows\img0.jpg",
        "C:\Windows\Web\Wallpaper\Theme1\img1.jpg",
        "C:\Windows\system32\oobe\info\backgrounds\backgroundDefault.jpg",
        "C:\Wallpaper\system-wallpaper.png"  # Custom wallpaper if exists
    )
    
    foreach ($wallpaper in $defaultWallpapers) {
        if (Test-Path $wallpaper) {
            $WallpaperPath = $wallpaper
            Write-Log "Using wallpaper: $WallpaperPath" -Color Cyan
            break
        }
    }
}

if (-not (Test-Path $WallpaperPath)) {
    Write-Log "ERROR: Wallpaper file not found: $WallpaperPath" -Color Red
    Write-Log "Please specify a valid wallpaper path or use -UseSystemDefault" -Color Yellow
    exit 1
}

Copy-Item -Path $WallpaperPath -Destination $SystemWallpaper -Force
Write-Log "Copied $WallpaperPath to $SystemWallpaper" -Color Cyan
$machine   = $env:COMPUTERNAME
$internal  = Get-InternalIP
$external  = Get-ExternalIP
$overlay   = "Machine: $machine`nInternal IP: $internal`nExternal IP: $external"
Add-WallpaperOverlay -ImagePath $SystemWallpaper -Text $overlay
$WallpaperPath = $SystemWallpaper

Write-Log "`n1. Setting wallpaper for current user..." -Color Yellow

# Set wallpaper for current user
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $WallpaperPath -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String"  # Fill
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String"

# Apply wallpaper immediately using correct API parameters
try {
    Add-Type @"
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    public static void SetWallpaper(string path) {
        SystemParametersInfo(20, 0, path, 0x01 | 0x02);
    }
}
"@
    [WallpaperAPI]::SetWallpaper($WallpaperPath)
    Write-Log "[OK] Wallpaper applied immediately" -Color Green
} catch {
    Write-Log "! Could not apply wallpaper immediately: $_" -Color Yellow
}

Write-Log "`n2. Setting up startup persistence..." -Color Yellow

# FIXED: Registry startup entry with proper API parameters
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$scriptCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"if (Test-Path '$WallpaperPath') { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value '$WallpaperPath' -Force; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force; rundll32.exe user32.dll,SystemParametersInfoW 20 0 '$WallpaperPath' 3 }`""

try {
    Set-ItemProperty -Path $registryPath -Name "WallpaperPersistence" -Value $scriptCommand
    Write-Log "[OK] Added registry startup entry" -Color Green
} catch {
    Write-Log "[FAIL] Failed to add registry startup entry: $_" -Color Red
}

# FIXED: Startup folder script with proper error handling
$startupScript = @"
@echo off
rem Wallpaper Persistence Script
timeout /t 3 /nobreak >nul 2>&1

rem Check if wallpaper file exists
if not exist "$WallpaperPath" (
    exit /b 0
)

rem Set wallpaper with correct API call
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value '$WallpaperPath' -Force; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force; Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class WP { [DllImport(\`"user32.dll\`")] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }'; [WP]::SystemParametersInfo(20, 0, '$WallpaperPath', 3) } catch { }"
"@

$startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WallpaperFix.bat"
try {
    Set-Content -Path $startupPath -Value $startupScript -Encoding ASCII
    Write-Log "[OK] Created startup folder script" -Color Green
} catch {
    Write-Log "[FAIL] Failed to create startup script: $_" -Color Red
}

Write-Log "`n3. Setting wallpaper for existing users..." -Color Yellow

# Apply wallpaper to all currently loaded user profiles
$userProfiles = Get-ChildItem "Registry::HKEY_USERS" | Where-Object { $_.Name -match "S-1-5-21-.*" }
foreach ($profile in $userProfiles) {
    $userSID = Split-Path $profile.Name -Leaf
    $userRegPath = "Registry::HKEY_USERS\$userSID\Control Panel\Desktop"

    if (Test-Path $userRegPath) {
        try {
            Set-RegistryValue -Path $userRegPath -Name "WallPaper" -Value $WallpaperPath -Type "String"
            Set-RegistryValue -Path $userRegPath -Name "WallpaperStyle" -Value "10" -Type "String"
            Set-RegistryValue -Path $userRegPath -Name "TileWallpaper" -Value "0" -Type "String"
            Write-Log "[OK] Configured for user SID: $userSID" -Color Green
        } catch {
            Write-Log "! Could not configure user SID: $userSID" -Color Yellow
        }
    }
}

# Apply wallpaper to offline user profiles by loading their registry hives
Write-Log "Checking offline user profiles..." -Color Yellow
$offlineProfiles = Get-ChildItem -Path 'C:\Users' -Directory |
    Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }
foreach ($profile in $offlineProfiles) {
    $ntUser = Join-Path $profile.FullName 'NTUSER.DAT'
    if (Test-Path $ntUser) {
        $hiveName = "TempHive_$($profile.Name)"
        if (Load-RegistryHive -HivePath $ntUser -HiveName $hiveName) {
            try {
                $hivePath = "Registry::HKEY_USERS\$hiveName\Control Panel\Desktop"
                Set-RegistryValue -Path $hivePath -Name "WallPaper" -Value $WallpaperPath -Type "String"
                Set-RegistryValue -Path $hivePath -Name "WallpaperStyle" -Value "10" -Type "String"
                Set-RegistryValue -Path $hivePath -Name "TileWallpaper" -Value "0" -Type "String"
                Write-Log "[OK] Configured offline profile: $($profile.Name)" -Color Green
            } finally {
                & reg.exe unload "HKU\$hiveName" 2>&1 | Out-Null
            }
        }
        # Hive was locked after retries
        else {
            Write-Log "! Skipping locked profile: $($profile.Name)" -Color Yellow
            try {
                $userStartup = Join-Path $profile.FullName 'AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup'
                if (-not (Test-Path $userStartup)) {
                    New-Item -ItemType Directory -Path $userStartup -Force | Out-Null
                }
                $userScript = Join-Path $userStartup 'WallpaperFix.bat'
                Set-Content -Path $userScript -Value $startupScript -Encoding ASCII
                Write-Log "[OK] Deferred wallpaper fix for $($profile.Name)" -Color Cyan
            } catch {
                Write-Log "! Could not defer wallpaper fix for $($profile.Name): $_" -Color Yellow
            }
        }
    }
}

Write-Log "`n4. Setting default wallpaper for new users..." -Color Yellow

# Set wallpaper for default user profile (new users)
$defaultUserPath = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultUserPath) {
    $mountResult = & reg.exe load "HKU\DefaultUserTemp" $defaultUserPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        try {
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "WallPaper" -Value $WallpaperPath -Type "String"
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String"
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String"
            Write-Log "[OK] Set default wallpaper for new users" -Color Green
        } finally {
            & reg.exe unload "HKU\DefaultUserTemp" 2>&1 | Out-Null
        }
    } else {
        Write-Log "! Could not mount default user registry: $mountResult" -Color Yellow
    }
}

Write-Log "`n5. Creating recovery tools..." -Color Yellow

# Create a recovery script
$recoveryScript = @"
# Wallpaper Recovery Script
# Run this if wallpaper doesn't persist

`$wallpaperPath = "$WallpaperPath"

if (-not (Test-Path `$wallpaperPath)) {
    Write-Host "Wallpaper file not found: `$wallpaperPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Restoring wallpaper..." -ForegroundColor Cyan

# Set registry values
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value `$wallpaperPath -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Force

# Apply wallpaper
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class WallpaperSetter { [DllImport("user32.dll")] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }'
[WallpaperSetter]::SystemParametersInfo(20, 0, `$wallpaperPath, 3)

Write-Host "Wallpaper restored!" -ForegroundColor Green
Read-Host "Press Enter to exit"
"@

$recoveryPath = "$env:USERPROFILE\Desktop\Restore-Wallpaper.ps1"
try {
    Set-Content -Path $recoveryPath -Value $recoveryScript -Encoding UTF8
    Write-Log "[OK] Created recovery script: $recoveryPath" -Color Green
} catch {
    Write-Log "! Could not create recovery script: $_" -Color Yellow
}

Write-Log "`n=== WALLPAPER PERSISTENCE FIX COMPLETE ===" -Color Green
Write-Log "Wallpaper: $WallpaperPath" -Color Cyan
Write-Log "`nThe wallpaper should now persist after restarts." -Color Cyan
Write-Log "If issues persist, run the recovery script on your desktop." -Color Yellow

# Show instructions for manual testing
Write-Log "`nTo test persistence:" -Color Yellow
Write-Log "1. Restart your computer" -Color Gray
Write-Log "2. Check if wallpaper is still applied" -Color Gray
Write-Log "3. If not, run: .\Restore-Wallpaper.ps1" -Color Gray
