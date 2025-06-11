# Apply a custom wallpaper for the current user

Write-Host "Setting initial wallpaper..." -ForegroundColor Cyan

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Download-Wallpaper {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -ErrorAction Stop
        return $true
    } catch {
        Write-Host "Failed to download wallpaper: $_" -ForegroundColor Red
        return $false
    }
}

function Set-Wallpaper {
    param([string]$WallpaperPath)
    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Wallpaper {
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        }
"@
        $SPI_SETDESKWALLPAPER = 0x0014
        $SPIF_UPDATEINIFILE = 0x01
        $SPIF_SENDCHANGE = 0x02
        $result = [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $WallpaperPath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)
        if ($result) {
            Write-Host "Wallpaper set successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to set wallpaper" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error setting wallpaper: $_" -ForegroundColor Red
        return $false
    }
}

$repoImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'
$wallpaperDir = 'C:\\wallpaper'
$wallpaperPath = Join-Path $wallpaperDir 'wallpaper.png'

if (-not (Test-Path $wallpaperDir)) {
    New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null
}

if (Test-Path $repoImage) {
    Copy-Item -Path $repoImage -Destination $wallpaperPath -Force
} else {
    $wallpaperUrl = 'https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/wallpaper/wallpaper.png'
    if (-not (Download-Wallpaper -Url $wallpaperUrl -OutputPath $wallpaperPath)) {
        Write-Host "Could not obtain wallpaper." -ForegroundColor Yellow
        return
    }
}

Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force

Set-Wallpaper -WallpaperPath $wallpaperPath

Write-Host "Initial wallpaper process completed" -ForegroundColor Cyan
