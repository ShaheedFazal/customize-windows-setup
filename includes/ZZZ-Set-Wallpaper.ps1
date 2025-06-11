# Apply a custom wallpaper for the current user
param([string]$WallpaperPath = '')

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DefaultImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'

if ([string]::IsNullOrWhiteSpace($WallpaperPath)) {
    $WallpaperPath = $DefaultImage
}

if (-not (Test-Path $WallpaperPath)) {
    Write-Host "Wallpaper file not found: $WallpaperPath" -ForegroundColor Red
    return
}

# Set registry values to configure the wallpaper style
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $WallpaperPath -Type "String" -Force
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force

# Apply the wallpaper immediately
Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
[Wallpaper]::SystemParametersInfo(20, 0, $WallpaperPath, 0x01 -bor 0x02) | Out-Null

Write-Host "Wallpaper applied: $WallpaperPath" -ForegroundColor Green
