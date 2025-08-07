# Configure default wallpaper for new user profiles and optionally enforce it via policy

Write-Host "[WALLPAPER] Configuring default wallpaper" -ForegroundColor Cyan

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'
$wallpaperDir = 'C:\wallpaper'
$wallpaperPath = Join-Path $wallpaperDir 'wallpaper.png'

# Ensure wallpaper directory exists and copy image
if (-not (Test-Path $wallpaperDir)) {
    New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null
}
if (Test-Path $repoImage) {
    Copy-Item -Path $repoImage -Destination $wallpaperPath -Force
    Write-Host "[WALLPAPER] Copied wallpaper to $wallpaperPath" -ForegroundColor Green
} else {
    Write-Host "[WALLPAPER] Repository image not found at $repoImage" -ForegroundColor Yellow
}

# Apply to default user profile
$defaultRegPath = 'HKU:\.DEFAULT\Control Panel\Desktop'
Set-RegistryValue -Path $defaultRegPath -Name 'Wallpaper' -Value $wallpaperPath -Type 'String' -Force
Set-RegistryValue -Path $defaultRegPath -Name 'WallpaperStyle' -Value '10' -Type 'String' -Force
Set-RegistryValue -Path $defaultRegPath -Name 'TileWallpaper' -Value '0' -Type 'String' -Force

# Enforce for all users via policy
$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
Set-RegistryValue -Path $policyPath -Name 'Wallpaper' -Value $wallpaperPath -Type 'String' -Force
Set-RegistryValue -Path $policyPath -Name 'WallpaperStyle' -Value '10' -Type 'String' -Force

Write-Host "[WALLPAPER] Default wallpaper configured" -ForegroundColor Cyan
