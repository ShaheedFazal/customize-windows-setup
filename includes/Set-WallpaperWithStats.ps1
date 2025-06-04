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
$pcModel       = (Get-CimInstance Win32_ComputerSystem).Model
$serialNumber  = (Get-CimInstance Win32_BIOS).SerialNumber

# Load image and overlay text
Add-Type -AssemblyName System.Drawing
$image     = [System.Drawing.Image]::FromFile($wallpaperImage)
$graphics  = [System.Drawing.Graphics]::FromImage($image)
$font      = New-Object System.Drawing.Font('Arial',14)
$brush     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)

$infoText      = "PC: $computerName`nModel: $pcModel`nSerial: $serialNumber`nWorkgroup: $workgroup`nWindows: $windowsVer"
$size          = $graphics.MeasureString($infoText,$font)

# leave extra space so the taskbar doesn't cover the overlay text
$bottomMargin  = 60
$x             = $image.Width  - $size.Width  - 10
$y             = $image.Height - $size.Height - $bottomMargin
$graphics.DrawString($infoText,$font,$brush,$x,$y)

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
