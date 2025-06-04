# Ensure winget is available
# If the 'winget' command-line tool is missing, attempt to install it
# automatically using the official App Installer package. If installation fails
# the script simply returns so that the parent process can decide how to
# continue.
if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] 'winget' is not available. Attempting to install App Installer..." -ForegroundColor Yellow
    try {
        $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetPath = Join-Path $env:TEMP "AppInstaller.msixbundle"
        Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath -UseBasicParsing
        Add-AppxPackage -Path $wingetPath -ForceApplicationShutdown
        Remove-Item $wingetPath -ErrorAction SilentlyContinue
        Write-Host "[OK] winget installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to install winget automatically: $_" -ForegroundColor Red
        return
    }
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] winget is still unavailable after installation attempt." -ForegroundColor Red
        return
    }
}

# Ensure C:\Scripts exists
# Creates a folder to store scripts such as update routines
$scriptFolder = "C:\Scripts"
if (-not (Test-Path $scriptFolder)) {
    New-Item -ItemType Directory -Path $scriptFolder | Out-Null
}

# Install Apps
# Defines a list of essential and commonly used applications grouped by category
$apps = @(
    # Runtimes & Dependencies (required by many desktop applications)
    @{ Name = ".NET Desktop Runtime 6"; Id = "Microsoft.DotNet.DesktopRuntime.6" },
    @{ Name = ".NET Desktop Runtime 7"; Id = "Microsoft.DotNet.DesktopRuntime.7" },
    @{ Name = ".NET Desktop Runtime 8"; Id = "Microsoft.DotNet.DesktopRuntime.8" },
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x64)"; Id = "Microsoft.VC++2015-2022Redist-x64" },
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x86)"; Id = "Microsoft.VC++2015-2022Redist-x86" },

    # Utilities (tools that support basic file and media operations)
    @{ Name = "7-Zip"; Id = "7zip.7zip" },  # File archiver
    @{ Name = "Notepad++"; Id = "Notepad++.Notepad++" },  # Advanced text editor
    @{ Name = "VLC Media Player"; Id = "VideoLAN.VLC" },  # Versatile media player

    # Communication (messaging and video call platforms)
    @{ Name = "Telegram"; Id = "Telegram.TelegramDesktop" },
    @{ Name = "Zoom"; Id = "Zoom.Zoom" },
    @{ Name = "Microsoft Teams"; Id = "Microsoft.Teams" },

    # Remote Access (remote desktop/support tool)
    @{ Name = "AnyDesk"; Id = "AnyDeskSoftwareGmbH.AnyDesk" },

    # Google Workspace Tools (for Chrome and Drive access)
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Google Drive"; Id = "Google.GoogleDrive" },

    # Office/Productivity (office suite for documents, spreadsheets, etc.)
    @{ Name = "LibreOffice"; Id = "TheDocumentFoundation.LibreOffice" },

    # Developer Tools (for scripting, coding, and terminal access)
    @{ Name = "PowerShell 7"; Id = "Microsoft.Powershell" },
    @{ Name = "Python"; Id = "Python.Python.3" },
    @{ Name = "Windows Terminal"; Id = "Microsoft.WindowsTerminal" }
)

# Loop through each app and install via winget
foreach ($app in $apps) {
    Write-Host "[INFO] Installing $($app.Name)..." -ForegroundColor Cyan
    try {
        winget install --id=$($app.Id) --accept-source-agreements --accept-package-agreements -e -h
        Write-Host "[OK] Installed $($app.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to install $($app.Name): $_" -ForegroundColor Red
    }
}

# Write Update Script
# This creates a PowerShell script to update all winget apps silently
$updateScriptPath = Join-Path $scriptFolder "Update-WingetApps.ps1"
$updateScriptContent = @'
# Silent update of all upgradable winget apps
winget upgrade --all --accept-source-agreements --accept-package-agreements
'@
Set-Content -Path $updateScriptPath -Value $updateScriptContent -Encoding UTF8

# Schedule Task
# This schedules the update script to run every Sunday at 8 AM as SYSTEM
$taskName = "Weekly Winget App Update"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updateScriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 8:00am

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Weekly winget updates" -RunLevel Highest -User "SYSTEM"
    Write-Host "[OK] Scheduled weekly update task as 'SYSTEM'" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to register scheduled task: $_" -ForegroundColor Red
}

# Download SetUserFTA for file association scripts
$setUserFtaUrl  = 'https://github.com/clechasseur/setuserfta/releases/download/v1.7.1/SetUserFTA.exe'
$setUserFtaPath = Join-Path $scriptFolder 'SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    try {
        Write-Host "Downloading SetUserFTA..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $setUserFtaUrl -OutFile $setUserFtaPath -UseBasicParsing
        Write-Host "[OK] SetUserFTA downloaded to $setUserFtaPath" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to download SetUserFTA: $_" -ForegroundColor Red
    }
}
