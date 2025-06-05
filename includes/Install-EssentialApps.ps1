# Ensure TLS 1.2 for GitHub downloads
if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

function Download-File {
    param(
        [string]$Url,
        [string]$Path
    )

    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
            return
        } catch {
            if ($i -eq $maxRetries) { throw }
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

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
        Download-File -Url $wingetUrl -Path $wingetPath
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
    @{ Name = "AnyDesk"; Id = "AnyDesk.AnyDesk" },

    # Google Workspace Tools (for Chrome and Drive access)
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Google Drive"; Id = "Google.GoogleDrive" },

    # Office/Productivity (office suite for documents, spreadsheets, etc.)
    @{ Name = "LibreOffice"; Id = "TheDocumentFoundation.LibreOffice" },

    # Developer Tools (for scripting, coding, and terminal access)
    # Use the official PowerShell package identifier. The old value
    # "Microsoft.Powershell" fails to resolve with winget.
    @{ Name = "PowerShell 7"; Id = "Microsoft.PowerShell" },
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
# Fetch a known working copy from qis/windows
$setUserFtaUrl  = 'https://github.com/qis/windows/blob/master/setup/SetUserFTA/SetUserFTA.exe'
$setUserFtaPath = Join-Path $scriptFolder 'SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    try {
        Write-Host "Downloading SetUserFTA..." -ForegroundColor Cyan
        Download-File -Url $setUserFtaUrl -Path $setUserFtaPath
        Write-Host "[OK] SetUserFTA downloaded to $setUserFtaPath" -ForegroundColor Green
    } catch {
        Write-Warning "SetUserFTA download failed: $($_.Exception.Message)"
    }
}
