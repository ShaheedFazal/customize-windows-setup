# Apply a custom wallpaper for the current user
param([string]$WallpaperPath = '')

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DefaultImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'
$BgInfoExe = Join-Path $ScriptRoot '..\wallpaper\Bginfo.exe'
$BgInfoSettings = Join-Path $ScriptRoot '..\wallpaper\WallpaperSettings'

# Startup configuration
$CommonStartup   = [Environment]::GetFolderPath('CommonStartup')
$ScriptFolder    = 'C:\\Scripts'
$PersistedScript = Join-Path $ScriptFolder 'Reload-Wallpaper.ps1'
$StartupCmd      = Join-Path $CommonStartup 'ReloadWallpaper.cmd'

# BGInfo download configuration
$BgInfoUrl = 'https://download.sysinternals.com/files/BGInfo.zip'
$BgInfoZip = Join-Path $env:TEMP 'BGInfo.zip'

# Ensure TLS 1.2 for downloads
if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

function Download-File {
    param([string]$Url, [string]$Path)
    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            if ($i -eq $maxRetries) { return $false }
            Start-Sleep -Seconds (2 * $i)
        }
    }
    return $false
}

if ([string]::IsNullOrWhiteSpace($WallpaperPath)) {
    $WallpaperPath = $DefaultImage
}

if (-not (Test-Path $WallpaperPath)) {
    Write-Host "Wallpaper file not found: $WallpaperPath" -ForegroundColor Red
    return
}

# Persist script and configure startup if running from the repository
$isPersisted = ($PSCommandPath -ieq $PersistedScript)
if (-not $isPersisted) {
    if (-not (Test-Path $ScriptFolder)) {
        New-Item -ItemType Directory -Path $ScriptFolder -Force | Out-Null
    }
    Copy-Item -Path $PSCommandPath -Destination $PersistedScript -Force

    if (-not (Test-Path $StartupCmd)) {
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PersistedScript`""
        Set-Content -Path $StartupCmd -Value $cmd -Encoding ASCII
        Write-Host "Startup wallpaper reload configured." -ForegroundColor Green
    }
}

# Download BGInfo if missing
if (-not (Test-Path $BgInfoExe)) {
    Write-Host 'BGInfo not found. Downloading...' -ForegroundColor Cyan
    if (Download-File -Url $BgInfoUrl -Path $BgInfoZip) {
        try {
            Expand-Archive -Path $BgInfoZip -DestinationPath (Split-Path $BgInfoExe) -Force
            Remove-Item $BgInfoZip -ErrorAction SilentlyContinue
            $downloaded = Get-ChildItem -Path (Split-Path $BgInfoExe) -Filter 'Bginfo*.exe' -Recurse | Select-Object -First 1
            if ($downloaded) {
                Move-Item $downloaded.FullName $BgInfoExe -Force
                Write-Host "BGInfo downloaded to $BgInfoExe" -ForegroundColor Green
            } else {
                Write-Warning 'BGInfo executable not found after extraction'
            }
        } catch {
            Write-Host "Failed to extract BGInfo: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host 'Failed to download BGInfo.' -ForegroundColor Yellow
    }
}

# Use BGInfo if available to apply the wallpaper with system details
if ((Test-Path $BgInfoExe) -and (Test-Path $BgInfoSettings)) {
    Write-Host "Applying wallpaper using BGInfo..." -ForegroundColor Cyan
    try {
        & $BgInfoExe $BgInfoSettings '/silent' '/nolicprompt' '/timer:0' '/accepteula'
        Write-Host "BGInfo applied wallpaper." -ForegroundColor Green
        return
    } catch {
        Write-Host "BGInfo failed: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host 'BGInfo not found, using standard method.' -ForegroundColor Yellow
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
