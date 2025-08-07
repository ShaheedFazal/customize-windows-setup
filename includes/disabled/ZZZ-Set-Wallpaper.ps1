# Apply a custom wallpaper for all users via policy

Write-Host "Configuring system wallpaper..." -ForegroundColor Cyan

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoImage = Join-Path $ScriptRoot '..\wallpaper\wallpaper.png'

$destDir = 'C:\Windows\Web\Wallpaper'
$destPath = Join-Path $destDir 'custom-wallpaper.png'

# Ensure destination directory exists
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host "Created wallpaper directory: $destDir" -ForegroundColor Green
}

# Copy wallpaper from repository
if (Test-Path $repoImage) {
    Copy-Item -Path $repoImage -Destination $destPath -Force
    Write-Host "Copied wallpaper from repository to $destPath" -ForegroundColor Green
} else {
    Write-Host "Repository wallpaper not found at $repoImage" -ForegroundColor Yellow
}

if (-not (Test-Path $destPath)) {
    Write-Host "Wallpaper file not found at $destPath" -ForegroundColor Red
    return
}

# Set policy registry values for all users
$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
Set-RegistryValue -Path $policyPath -Name 'Wallpaper' -Value $destPath -Type 'String' -Force | Out-Null
Set-RegistryValue -Path $policyPath -Name 'WallpaperStyle' -Value '10' -Type 'String' -Force | Out-Null

# Refresh wallpaper and policies
Start-Process -FilePath 'rundll32.exe' -ArgumentList 'user32.dll, UpdatePerUserSystemParameters' -Wait | Out-Null
try {
    Start-Process -FilePath 'gpupdate.exe' -ArgumentList '/target:computer /force' -Wait | Out-Null
} catch {
    Write-Host 'gpupdate.exe not found, skipping policy refresh' -ForegroundColor Yellow
}

Write-Host "System wallpaper policy applied: $destPath" -ForegroundColor Green
Write-Host "Wallpaper configuration completed" -ForegroundColor Cyan
