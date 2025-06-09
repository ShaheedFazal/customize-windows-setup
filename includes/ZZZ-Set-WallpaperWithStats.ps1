# Simple Wallpaper Persistence Fix Script
# Standalone script to fix wallpaper persistence issues

#Requires -RunAsAdministrator

param(
    [string]$WallpaperPath = "",
    [switch]$UseSystemDefault
)

Write-Host "=== WALLPAPER PERSISTENCE FIX ===" -ForegroundColor Cyan

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
        Write-Host "✓ Set $Name in $Path" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "✗ Failed to set $Name in $Path : $_" -ForegroundColor Red
        return $false
    }
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
            Write-Host "Using wallpaper: $WallpaperPath" -ForegroundColor Cyan
            break
        }
    }
}

if (-not (Test-Path $WallpaperPath)) {
    Write-Host "ERROR: Wallpaper file not found: $WallpaperPath" -ForegroundColor Red
    Write-Host "Please specify a valid wallpaper path or use -UseSystemDefault" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n1. Setting wallpaper for current user..." -ForegroundColor Yellow

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
    Write-Host "✓ Wallpaper applied immediately" -ForegroundColor Green
} catch {
    Write-Host "! Could not apply wallpaper immediately: $_" -ForegroundColor Yellow
}

Write-Host "`n2. Setting up startup persistence..." -ForegroundColor Yellow

# FIXED: Registry startup entry with proper API parameters
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$scriptCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"if (Test-Path '$WallpaperPath') { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value '$WallpaperPath' -Force; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force; rundll32.exe user32.dll,SystemParametersInfoW 20 0 '$WallpaperPath' 3 }`""

try {
    Set-ItemProperty -Path $registryPath -Name "WallpaperPersistence" -Value $scriptCommand
    Write-Host "✓ Added registry startup entry" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to add registry startup entry: $_" -ForegroundColor Red
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
    Write-Host "✓ Created startup folder script" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to create startup script: $_" -ForegroundColor Red
}

Write-Host "`n3. Setting wallpaper for existing users..." -ForegroundColor Yellow

# Set wallpaper for all loaded user profiles
$userProfiles = Get-ChildItem "Registry::HKEY_USERS" | Where-Object { $_.Name -match "S-1-5-21-.*" }

foreach ($profile in $userProfiles) {
    $userSID = Split-Path $profile.Name -Leaf
    $userRegPath = "Registry::HKEY_USERS\$userSID\Control Panel\Desktop"
    
    if (Test-Path $userRegPath) {
        try {
            Set-RegistryValue -Path $userRegPath -Name "WallPaper" -Value $WallpaperPath -Type "String"
            Set-RegistryValue -Path $userRegPath -Name "WallpaperStyle" -Value "10" -Type "String"
            Set-RegistryValue -Path $userRegPath -Name "TileWallpaper" -Value "0" -Type "String"
            Write-Host "✓ Configured for user SID: $userSID" -ForegroundColor Green
        } catch {
            Write-Host "! Could not configure user SID: $userSID" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n4. Setting default wallpaper for new users..." -ForegroundColor Yellow

# Set wallpaper for default user profile (new users)
$defaultUserPath = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultUserPath) {
    $mountResult = & reg.exe load "HKU\DefaultUserTemp" $defaultUserPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        try {
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "WallPaper" -Value $WallpaperPath -Type "String"
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String"
            Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUserTemp\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String"
            Write-Host "✓ Set default wallpaper for new users" -ForegroundColor Green
        } finally {
            & reg.exe unload "HKU\DefaultUserTemp" 2>&1 | Out-Null
        }
    } else {
        Write-Host "! Could not mount default user registry: $mountResult" -ForegroundColor Yellow
    }
}

Write-Host "`n5. Creating recovery tools..." -ForegroundColor Yellow

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
    Write-Host "✓ Created recovery script: $recoveryPath" -ForegroundColor Green
} catch {
    Write-Host "! Could not create recovery script: $_" -ForegroundColor Yellow
}

Write-Host "`n=== WALLPAPER PERSISTENCE FIX COMPLETE ===" -ForegroundColor Green
Write-Host "Wallpaper: $WallpaperPath" -ForegroundColor Cyan
Write-Host "`nThe wallpaper should now persist after restarts." -ForegroundColor Cyan
Write-Host "If issues persist, run the recovery script on your desktop." -ForegroundColor Yellow

# Show instructions for manual testing
Write-Host "`nTo test persistence:" -ForegroundColor Yellow
Write-Host "1. Restart your computer" -ForegroundColor Gray
Write-Host "2. Check if wallpaper is still applied" -ForegroundColor Gray
Write-Host "3. If not, run: .\Restore-Wallpaper.ps1" -ForegroundColor Gray
