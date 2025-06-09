# FIXED: Enhanced wallpaper with system information - PROPER PERSISTENCE
# Addresses all identified persistence issues

#Requires -RunAsAdministrator

# Load shared functions and template functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
$wallpaperImage = Join-Path $repoRoot 'wallpaper\wallpaper.png'

# Load template functions for proper default user handling
$templateFunctionsPath = Join-Path $scriptDir 'Profile-Template-Functions.ps1'
if (Test-Path $templateFunctionsPath) {
    . $templateFunctionsPath
}

if (-not (Test-Path $wallpaperImage)) {
    Write-Host "Wallpaper file not found: $wallpaperImage" -ForegroundColor Yellow
    Write-Host "Please add wallpaper.png to the wallpaper folder" -ForegroundColor Yellow
    return
}

# Configuration
$font = "Arial"
$size = 12.0
$textPaddingLeft = 10
$textPaddingTop = 10
$textItemSpace = 3

# Gather system information
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = (Get-CimInstance Win32_Processor).Name.Replace("Intel(R) Core(TM) ", "").Replace("(R)", "").Replace("(TM)", "")
$bios = Get-CimInstance Win32_BIOS
$bootTimeSpan = (New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date))
$ip = (Get-NetIPAddress | Where-Object {$_.InterfaceAlias -like "*Ethernet*" -and $_.AddressFamily -eq "IPv4"}).IPAddress | Select-Object -First 1

$systemInfo = [ordered]@{
    'Computer' = $env:COMPUTERNAME
    'Model' = $cs.Model
    'Serial' = $bios.SerialNumber
    'CPU' = $cpu
    'RAM' = "$([math]::round($os.TotalVisibleMemorySize / 1MB))GB"
    'OS' = "$($os.Caption.Replace('Microsoft ', '')) ($($os.OSArchitecture))"
    'Workgroup' = $cs.Workgroup
    'IP' = if ($ip) { $ip } else { "Not connected" }
    'Boot' = $os.LastBootUpTime.ToString("dd/MM/yyyy HH:mm")
    'Uptime' = "$($bootTimeSpan.Days)d $($bootTimeSpan.Hours)h"
}

# FIXED: Proper C# wallpaper API with correct parameters
Add-Type @"
using System.Runtime.InteropServices;
namespace Wallpaper
{
    public class Setter {
        public const int SetDesktopWallpaper = 20;
        public const int UpdateIniFile = 0x01;
        public const int SendWinIniChange = 0x02;
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
        
        [DllImport("user32.dll", SetLastError = true)]
        private static extern int UpdatePerUserSystemParameters(int dwFlags, int bEnable);
        
        public static void UpdateWallpaper (string path)
        {
            SystemParametersInfo( SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange );
            // FIXED: Add small delay to ensure file is ready
            System.Threading.Thread.Sleep(500);
            UpdatePerUserSystemParameters(1, 1);
        }
    }
}
"@

function New-WallpaperWithSystemInfo {
    param(
        [Parameter(Mandatory=$True)]
        [object] $data,
        [Parameter(Mandatory=$True)]
        [string] $inputImage,
        [Parameter(Mandatory=$True)]
        [string] $outputPath
    )

    # Load required assemblies
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    # Create brushes
    $foreBrush = [System.Drawing.Brushes]::White
    $backBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(192, 0, 0, 0))

    # Get screen resolution
    $screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object Primary | Select-Object -ExpandProperty Bounds
    
    # Create background bitmap and load source image
    $background = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
    $sourceImage = New-Object System.Drawing.Bitmap($inputImage)
    
    # Create graphics object
    $graphics = [System.Drawing.Graphics]::FromImage($background)
    
    # Draw source image to fill screen
    $imageRect = New-Object System.Drawing.RectangleF(0, 0, $screen.Width, $screen.Height)
    $graphics.DrawImage($sourceImage, $imageRect)
    
    # Calculate text dimensions
    $maxKeyWidth = 0
    $maxValWidth = 0
    $totalHeight = 0
    
    foreach ($item in $data.GetEnumerator()) {
        $keyText = "$($item.Name): "
        $valText = "$($item.Value)"
        
        $keyFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Bold)
        $valFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Regular)
        
        $keySize = $graphics.MeasureString($keyText, $keyFont)
        $valSize = $graphics.MeasureString($valText, $valFont)
        
        $maxKeyWidth = [math]::Max($maxKeyWidth, $keySize.Width)
        $maxValWidth = [math]::Max($maxValWidth, $valSize.Width)
        $totalHeight += [math]::Max($keySize.Height, $valSize.Height) + $textItemSpace
        
        $keyFont.Dispose()
        $valFont.Dispose()
    }
    
    # Calculate background rectangle position (bottom-right)
    $textBgWidth = $maxKeyWidth + $maxValWidth + ($textPaddingLeft * 2)
    $textBgHeight = $totalHeight + $textPaddingTop
    $textBgX = $screen.Width - $textBgWidth
    $textBgY = $screen.Height - $textBgHeight - 60  # 60px margin for taskbar
    
    # Draw background rectangle
    $textBgRect = New-Object System.Drawing.RectangleF($textBgX, $textBgY, $textBgWidth, $textBgHeight)
    $graphics.FillRectangle($backBrush, $textBgRect)
    
    # Draw text items
    $currentY = $textBgY + $textPaddingTop
    foreach ($item in $data.GetEnumerator()) {
        $keyText = "$($item.Name): "
        $valText = "$($item.Value)"
        
        $keyFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Bold)
        $valFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Regular)
        
        $keyX = $textBgX + $textPaddingLeft
        $valX = $textBgX + $textPaddingLeft + $maxKeyWidth
        
        $graphics.DrawString($keyText, $keyFont, $foreBrush, $keyX, $currentY)
        $graphics.DrawString($valText, $valFont, $foreBrush, $valX, $currentY)
        
        $currentY += $size + $textItemSpace + 4
        
        $keyFont.Dispose()
        $valFont.Dispose()
    }
    
    # Save the image
    $background.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    
    # Clean up
    $graphics.Dispose()
    $background.Dispose()
    $sourceImage.Dispose()
    $backBrush.Dispose()
    
    Write-Host "[WALLPAPER] Generated: $outputPath" -ForegroundColor Green
    return $outputPath
}

function Set-WallpaperWithProperAPI {
    param([string]$WallpaperPath)
    
    if (-not (Test-Path $WallpaperPath)) {
        Write-Host "[WALLPAPER ERROR] File not found: $WallpaperPath" -ForegroundColor Red
        return $false
    }
    
    try {
        # FIXED: Set registry values first, then call API with delay
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $WallpaperPath -Type "String" -Force
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force  # Fill
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force
        
        # FIXED: Wait for registry changes to be committed
        Start-Sleep -Milliseconds 500
        
        # Apply wallpaper using improved API
        [Wallpaper.Setter]::UpdateWallpaper($WallpaperPath)
        
        # FIXED: Force desktop refresh
        Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class DesktopRefresh {
                [DllImport("shell32.dll")]
                public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
            }
"@
        [DesktopRefresh]::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
        
        Write-Host "[WALLPAPER] Successfully applied: $WallpaperPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[WALLPAPER ERROR] Failed to set wallpaper: $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "[WALLPAPER] Starting FIXED wallpaper configuration..." -ForegroundColor Cyan

# Create system wallpaper directory
$systemWallpaperDir = "C:\Wallpaper"
if (-not (Test-Path $systemWallpaperDir)) {
    New-Item -ItemType Directory -Path $systemWallpaperDir -Force | Out-Null
    Write-Host "[WALLPAPER] Created system directory: $systemWallpaperDir" -ForegroundColor Green
}

# Generate system wallpaper
$systemWallpaperPath = Join-Path $systemWallpaperDir "system-wallpaper.png"
New-WallpaperWithSystemInfo -data $systemInfo -inputImage $wallpaperImage -outputPath $systemWallpaperPath | Out-Null

# 1. Set wallpaper for current user with FIXED API
Write-Host "`n1. Setting wallpaper for current user ($env:USERNAME)..." -ForegroundColor Cyan
$success = Set-WallpaperWithProperAPI -WallpaperPath $systemWallpaperPath

# 2. Set wallpaper for all existing users
Write-Host "`n2. Setting wallpaper for all existing users..." -ForegroundColor Cyan
$userProfiles = Get-CimInstance Win32_UserProfile | Where-Object { 
    $_.Special -eq $false -and 
    $_.LocalPath -notlike "*\Administrator*" -and
    $_.LocalPath -notlike "*\Guest*" -and
    $_.LocalPath -notlike "*\DefaultAppPool*" -and
    (Test-Path $_.LocalPath)
}

foreach ($profile in $userProfiles) {
    $userName = Split-Path $profile.LocalPath -Leaf
    try {
        $userRegPath = "Registry::HKEY_USERS\$($profile.SID)\Control Panel\Desktop"
        if (Test-Path "Registry::HKEY_USERS\$($profile.SID)") {
            Set-RegistryValue -Path $userRegPath -Name "WallPaper" -Value $systemWallpaperPath -Type "String" -Force
            Set-RegistryValue -Path $userRegPath -Name "WallpaperStyle" -Value "10" -Type "String" -Force
            Set-RegistryValue -Path $userRegPath -Name "TileWallpaper" -Value "0" -Type "String" -Force
            Write-Host "[WALLPAPER] Configured for user: $userName" -ForegroundColor Green
        }
    } catch {
        Write-Host "[WALLPAPER] Failed to configure for user: $userName" -ForegroundColor Yellow
    }
}

# 3. FIXED: Set default wallpaper using proper template functions
Write-Host "`n3. Setting default wallpaper for new users..." -ForegroundColor Cyan

if (Get-Command "Mount-DefaultUserHive" -ErrorAction SilentlyContinue) {
    if (Mount-DefaultUserHive) {
        try {
            $defaultDesktopPath = "Registry::HKEY_USERS\DEFAULT_TEMPLATE\Control Panel\Desktop"
            Set-RegistryValue -Path $defaultDesktopPath -Name "WallPaper" -Value $systemWallpaperPath -Type "String" -Force
            Set-RegistryValue -Path $defaultDesktopPath -Name "WallpaperStyle" -Value "10" -Type "String" -Force
            Set-RegistryValue -Path $defaultDesktopPath -Name "TileWallpaper" -Value "0" -Type "String" -Force
            Write-Host "[WALLPAPER] Set default wallpaper using template functions" -ForegroundColor Green
        }
        catch {
            Write-Host "[WALLPAPER] Failed to set default wallpaper: $_" -ForegroundColor Red
        }
        finally {
            Dismount-DefaultUserHive | Out-Null
        }
    }
} else {
    Write-Host "[WALLPAPER] Template functions not available, using fallback method" -ForegroundColor Yellow
    # Fallback to original method with better error handling
    $defaultUserPath = "C:\Users\Default"
    if (Test-Path $defaultUserPath) {
        $ntUserPath = Join-Path $defaultUserPath "NTUSER.DAT"
        if (Test-Path $ntUserPath) {
            $result = & reg.exe load "HKU\DefaultUser" $ntUserPath 2>&1
            if ($LASTEXITCODE -eq 0) {
                try {
                    Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "WallPaper" -Value $systemWallpaperPath -Type "String" -Force
                    Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force
                    Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force
                    Write-Host "[WALLPAPER] Set default wallpaper (fallback method)" -ForegroundColor Green
                }
                finally {
                    & reg.exe unload "HKU\DefaultUser" 2>&1 | Out-Null
                }
            } else {
                Write-Host "[WALLPAPER] Failed to mount default user hive: $result" -ForegroundColor Red
            }
        }
    }
}

# 4. FIXED: Create robust startup persistence
Write-Host "`n4. Creating ROBUST startup persistence..." -ForegroundColor Cyan

# FIXED Registry startup with file validation
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$scriptCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"if (Test-Path 'C:\Wallpaper\system-wallpaper.png') { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value 'C:\Wallpaper\system-wallpaper.png' -Force; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force; rundll32.exe user32.dll,UpdatePerUserSystemParameters 1 1 }`""
Set-ItemProperty -Path $registryPath -Name "SystemWallpaper" -Value $scriptCommand
Write-Host "✓ Added ROBUST registry startup entry" -ForegroundColor Green

# FIXED Startup folder script with proper error handling
$startupScript = @"
@echo off
rem FIXED Wallpaper Persistence Script
timeout /t 5 /nobreak >nul 2>&1

rem Check if wallpaper file exists
if not exist "C:\Wallpaper\system-wallpaper.png" (
    echo Wallpaper file not found, skipping update
    exit /b 0
)

rem Set wallpaper with proper error handling
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value 'C:\Wallpaper\system-wallpaper.png' -Force; Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Force; rundll32.exe user32.dll,UpdatePerUserSystemParameters 1 1 } catch { exit 1 }"

rem Success
exit /b 0
"@

$startupPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\UpdateWallpaper.bat"
Set-Content -Path $startupPath -Value $startupScript -Encoding ASCII
Write-Host "✓ Created ROBUST startup folder script" -ForegroundColor Green

# 5. Create recovery script for manual execution
$recoveryScript = @"
# Wallpaper Recovery Script
# Run this if wallpaper stops persisting

`$wallpaperPath = "C:\Wallpaper\system-wallpaper.png"

if (-not (Test-Path `$wallpaperPath)) {
    Write-Host "Wallpaper file not found: `$wallpaperPath" -ForegroundColor Red
    exit 1
}

Write-Host "Restoring wallpaper persistence..." -ForegroundColor Cyan

# Set registry values
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value `$wallpaperPath -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Force

# Apply changes
rundll32.exe user32.dll,UpdatePerUserSystemParameters 1 1

Write-Host "Wallpaper restored successfully!" -ForegroundColor Green
"@

$recoveryPath = Join-Path $systemWallpaperDir "Restore-Wallpaper.ps1"
Set-Content -Path $recoveryPath -Value $recoveryScript -Encoding UTF8
Write-Host "✓ Created recovery script: $recoveryPath" -ForegroundColor Green

Write-Host "`n=== WALLPAPER CONFIGURATION COMPLETE (FIXED) ===" -ForegroundColor Yellow
Write-Host "✓ Current user wallpaper applied with proper API" -ForegroundColor Green
Write-Host "✓ All existing user profiles configured" -ForegroundColor Green  
Write-Host "✓ Default user profile configured using proper template functions" -ForegroundColor Green
Write-Host "✓ ROBUST startup persistence with error handling" -ForegroundColor Green
Write-Host "✓ Recovery script created for troubleshooting" -ForegroundColor Green
Write-Host "`nThe wallpaper should now persist properly after restarts!" -ForegroundColor Cyan
