# Enhanced wallpaper with system information for ALL users
# Based on dieseltravis PS-BGInfo approach
# Uses shared functions and existing wallpaper folder structure

#Requires -RunAsAdministrator

# Load shared functions (assuming they're in the same directory or already loaded)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path $scriptDir -Parent
$wallpaperImage = Join-Path $repoRoot 'wallpaper\wallpaper.png'

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

# Add C# code for proper wallpaper setting
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
        public static void UpdateWallpaper (string path)
        {
            SystemParametersInfo( SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange );
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

    # Use system data as-is (no user-specific info)
    $displayData = $data

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
    
    foreach ($item in $displayData.GetEnumerator()) {
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
    foreach ($item in $displayData.GetEnumerator()) {
        $keyText = "$($item.Name): "
        $valText = "$($item.Value)"
        
        $keyFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Bold)
        $valFont = New-Object System.Drawing.Font($font, $size, [System.Drawing.FontStyle]::Regular)
        
        # Use simple coordinates instead of rectangles
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

function Set-WallpaperForUser {
    param(
        [string]$UserSID,
        [string]$WallpaperPath,
        [string]$UserName = "Unknown"
    )
    
    try {
        # Use shared registry function to set wallpaper for user
        $userRegPath = "Registry::HKEY_USERS\$UserSID\Control Panel\Desktop"
        
        if (Test-Path "Registry::HKEY_USERS\$UserSID") {
            Set-RegistryValue -Path $userRegPath -Name "WallPaper" -Value $WallpaperPath -Type "String" -Force
            Set-RegistryValue -Path $userRegPath -Name "WallpaperStyle" -Value "10" -Type "String" -Force  # Fill
            Set-RegistryValue -Path $userRegPath -Name "TileWallpaper" -Value "0" -Type "String" -Force
            
            Write-Host "[WALLPAPER] Applied for user: $UserName" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "[WALLPAPER ERROR] Failed to set wallpaper for user $UserName : $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "[WALLPAPER] Starting enhanced wallpaper configuration for all users..." -ForegroundColor Cyan

# Create system wallpaper directory
$systemWallpaperDir = "C:\Wallpaper"
if (-not (Test-Path $systemWallpaperDir)) {
    New-Item -ItemType Directory -Path $systemWallpaperDir -Force | Out-Null
    Write-Host "[WALLPAPER] Created system directory: $systemWallpaperDir" -ForegroundColor Green
}

# Generate single system wallpaper (without user-specific info)
$systemWallpaperPath = Join-Path $systemWallpaperDir "system-wallpaper.png"
New-WallpaperWithSystemInfo -data $systemInfo -inputImage $wallpaperImage -outputPath $systemWallpaperPath | Out-Null

Write-Host "[WALLPAPER] Generated system wallpaper: $systemWallpaperPath" -ForegroundColor Green

# 1. Set wallpaper for current user
Write-Host "`n1. Setting wallpaper for current user ($env:USERNAME)..." -ForegroundColor Cyan

# Generate wallpaper for current user
New-WallpaperWithSystemInfo -data $systemInfo -inputImage $wallpaperImage -outputPath $systemWallpaperPath | Out-Null

# Apply wallpaper using shared registry functions
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $systemWallpaperPath -Type "String" -Force
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force  # Fill
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force

# Apply immediately using C# API
[Wallpaper.Setter]::UpdateWallpaper($systemWallpaperPath)
Write-Host "[WALLPAPER] Applied for current user: $env:USERNAME" -ForegroundColor Green

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
    
    # Set same wallpaper for all users
    try {
        Set-WallpaperForUser -UserSID $profile.SID -WallpaperPath $systemWallpaperPath -UserName $userName
    } catch {
        Write-Host "[WALLPAPER] Failed to configure wallpaper for user: $userName" -ForegroundColor Yellow
    }
}

# 3. Set default wallpaper for new users
Write-Host "`n3. Setting default wallpaper for new users..." -ForegroundColor Cyan
$defaultUserPath = "C:\Users\Default"
if (Test-Path $defaultUserPath) {
    # Mount default user registry and set wallpaper using shared functions
    reg load "HKU\DefaultUser" "$defaultUserPath\NTUSER.DAT" 2>$null
    if (Test-Path "Registry::HKEY_USERS\DefaultUser") {
        Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "WallPaper" -Value $systemWallpaperPath -Type "String" -Force
        Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force
        Set-RegistryValue -Path "Registry::HKEY_USERS\DefaultUser\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force
        
        reg unload "HKU\DefaultUser" 2>$null
        Write-Host "[WALLPAPER] Set default wallpaper for new users" -ForegroundColor Green
    }
}

# 4. Create simple startup script for future updates
Write-Host "`n4. Creating startup script for wallpaper updates..." -ForegroundColor Cyan
$startupDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$startupScript = Join-Path $startupDir "UpdateWallpaper.bat"

$batchContent = @"
@echo off
REM Update wallpaper with current system info on startup
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& {
    try {
        `$wallpaperScript = '$($MyInvocation.MyCommand.Path)'
        if (Test-Path `$wallpaperScript) {
            & `$wallpaperScript
        }
    } catch {
        # Silent fail - don't show errors to users
    }
}"
"@

try {
    Set-Content -Path $startupScript -Value $batchContent -Encoding ASCII
    Write-Host "[WALLPAPER] Created startup script: $startupScript" -ForegroundColor Green
} catch {
    Write-Host "[WALLPAPER] Could not create startup script (not critical): $_" -ForegroundColor Yellow
}

Write-Host "`n=== WALLPAPER CONFIGURATION COMPLETE ===" -ForegroundColor Yellow
Write-Host "✓ Current user wallpaper applied immediately" -ForegroundColor Green
Write-Host "✓ All existing user profiles configured" -ForegroundColor Green  
Write-Host "✓ Default user profile configured for new users" -ForegroundColor Green
Write-Host "✓ Startup script created for updates" -ForegroundColor Green
Write-Host "`nSingle wallpaper file: $systemWallpaperPath" -ForegroundColor Cyan
Write-Host "All users will use the same wallpaper with system information" -ForegroundColor Cyan
Write-Host "The wallpaper will persist after restarts and show current system info" -ForegroundColor Cyan
