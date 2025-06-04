# Configure pinned Start menu apps

# Clears existing pins (except File Explorer) and pins Chrome, Telegram, WhatsApp Web and Gemini.

Write-Host "[INFO] Configuring Start menu pins..." -ForegroundColor Cyan

# Locate Chrome executable for the web shortcuts (WhatsApp Web and Gemini)

$chromeExe = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
if (-not $chromeExe) {
    $paths = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe','C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe'
    foreach ($p in $paths) { if (Test-Path $p) { $chromeExe = $p; break } }
}
if (-not $chromeExe) {
    Write-Host "[ERROR] Google Chrome not found. Skipping Start menu pin configuration." -ForegroundColor Red
    return
}

$programs = [Environment]::GetFolderPath('Programs')
# Create WhatsApp Web shortcut in the Start Menu if it doesn't exist

$whatsAppLnk = Join-Path $programs 'WhatsApp Web.lnk'
if (-not (Test-Path $whatsAppLnk)) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($whatsAppLnk)
    $shortcut.TargetPath = $chromeExe
    $shortcut.Arguments = '--new-window https://web.whatsapp.com/'
    $shortcut.IconLocation = "$chromeExe,0"
    $shortcut.Save()
}

# Create Gemini shortcut in the Start Menu if it doesn't exist
$geminiLnk = Join-Path $programs 'Gemini.lnk'
if (-not (Test-Path $geminiLnk)) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($geminiLnk)
    $shortcut.TargetPath = $chromeExe
    $shortcut.Arguments = '--new-window https://gemini.google.com/app'
    $shortcut.IconLocation = "$chromeExe,0"
    $shortcut.Save()
}


# Define layout JSON with the desired pins
$layoutJson = @"
{
    ""pinnedList"": [
        { ""desktopAppLink"": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\System Tools\\File Explorer.lnk" },
        { ""desktopAppLink"": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Google Chrome.lnk" },
        { ""desktopAppLink"": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Telegram.lnk" },
        { ""desktopAppLink"": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\WhatsApp Web.lnk" },
        { ""desktopAppLink"": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Gemini.lnk" }
    ],
    ""appliedInFullScreenMode"": false
}
"@

$tempJson = Join-Path $env:TEMP 'StartPins.json'
Set-Content -Path $tempJson -Value $layoutJson -Encoding UTF8

try {
    # Apply layout for the current user and set it as the default for new accounts
    Import-StartLayout -LayoutPath $tempJson
    Import-StartLayout -LayoutPath $tempJson -MountPath $env:SystemDrive\
    Write-Host "[OK] Start menu layout applied." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to apply Start menu layout: $_" -ForegroundColor Red
}

Remove-Item $tempJson -ErrorAction SilentlyContinue
