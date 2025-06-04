# Set a custom wallpaper and overlay system information on the image

# Determine repository root based on this script's location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path $scriptDir -Parent

# Path to wallpaper image relative to repo root.
# Update the filename to match the image you add to the `wallpaper` folder.
$wallpaperImage = Join-Path $repoRoot 'wallpaper\wallpaper.png'

if (-not (Test-Path $wallpaperImage)) {
    Write-Host "Wallpaper file not found: $wallpaperImage" -ForegroundColor Yellow
    return
}

# Gather system information
$computerName  = $env:COMPUTERNAME
$workgroup     = (Get-CimInstance Win32_ComputerSystem).Workgroup
$windowsVer    = (Get-CimInstance Win32_OperatingSystem).Caption

# Load image and overlay text
Add-Type -AssemblyName System.Drawing
$image     = [System.Drawing.Image]::FromFile($wallpaperImage)
$graphics  = [System.Drawing.Graphics]::FromImage($image)
$font      = New-Object System.Drawing.Font('Arial',14)
$brush     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)

$infoText  = "PC: $computerName`nWorkgroup: $workgroup`nWindows: $windowsVer"
$graphics.DrawString($infoText,$font,$brush,10,10)

# Save the temporary bitmap (wallpaper must be BMP format)
$tempBmp   = Join-Path $env:TEMP 'wallpaper-with-stats.bmp'
$image.Save($tempBmp, [System.Drawing.Imaging.ImageFormat]::Bmp)

# Clean up objects
$graphics.Dispose()
$image.Dispose()
$brush.Dispose()
$font.Dispose()

# Apply the new wallpaper
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $tempBmp
rundll32.exe user32.dll,UpdatePerUserSystemParameters
