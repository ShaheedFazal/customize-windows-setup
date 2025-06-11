# Apply a custom wallpaper for the current user - FIXED VERSION

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
        # Check if the type already exists before adding it
        $typeExists = $false
        try {
            [Wallpaper] | Out-Null
            $typeExists = $true
        } catch {
            $typeExists = $false
        }

        if (-not $typeExists) {
            Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class Wallpaper {
                [DllImport("user32.dll", CharSet = CharSet.Auto)]
                public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
            }
"@
        }

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

# Alternative method using rundll32 if the C# approach fails
function Set-WallpaperAlternative {
    param([string]$WallpaperPath)
    try {
        # Method 1: Registry + rundll32
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $WallpaperPath -Force
        
        # Refresh the desktop
        $result = Start-Process -FilePath "rundll32.exe" -ArgumentList "user32.dll,UpdatePerUserSystemParameters ,1 ,True" -Wait -PassThru
        
        if ($result.ExitCode -eq 0) {
            Write-Host "Wallpaper set successfully using alternative method" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Alternative wallpaper method failed" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error with alternative wallpaper method: $_" -ForegroundColor Red
        return $false
    }
}

$repoImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'
$wallpaperDir = 'C:\wallpaper'
$wallpaperPath = Join-Path $wallpaperDir 'wallpaper.png'

# Ensure wallpaper directory exists
if (-not (Test-Path $wallpaperDir)) {
    New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null
    Write-Host "Created wallpaper directory: $wallpaperDir" -ForegroundColor Green
}

# Get wallpaper from repo or download
if (Test-Path $repoImage) {
    Copy-Item -Path $repoImage -Destination $wallpaperPath -Force
    Write-Host "Copied wallpaper from repository" -ForegroundColor Green
} else {
    Write-Host "Repository wallpaper not found, downloading default..." -ForegroundColor Yellow
    $wallpaperUrl = 'https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/wallpaper/wallpaper.png'
    if (-not (Download-Wallpaper -Url $wallpaperUrl -OutputPath $wallpaperPath)) {
        Write-Host "Could not obtain wallpaper." -ForegroundColor Yellow
        return
    }
}

# Verify wallpaper file exists
if (-not (Test-Path $wallpaperPath)) {
    Write-Host "Wallpaper file not found at: $wallpaperPath" -ForegroundColor Red
    return
}

# Set wallpaper style settings
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -Type "String" -Force
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String" -Force

# Try primary method, fall back to alternative if needed
$success = Set-Wallpaper -WallpaperPath $wallpaperPath
if (-not $success) {
    Write-Host "Primary method failed, trying alternative..." -ForegroundColor Yellow
    $success = Set-WallpaperAlternative -WallpaperPath $wallpaperPath
}

if ($success) {
    Write-Host "Wallpaper successfully applied: $wallpaperPath" -ForegroundColor Green
} else {
    Write-Host "Failed to set wallpaper despite multiple attempts" -ForegroundColor Red
}

Write-Host "Initial wallpaper process completed" -ForegroundColor Cyan
