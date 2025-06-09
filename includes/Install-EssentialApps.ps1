# Ensure TLS 1.2 for GitHub downloads
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

# Copy a shortcut from the Start Menu to the public desktop
function Add-DesktopShortcut {
    param([string]$AppName)

    $startDir   = [Environment]::GetFolderPath('CommonPrograms')
    $desktopDir = [Environment]::GetFolderPath('CommonDesktopDirectory')

    $shortcut = Get-ChildItem -Path $startDir -Include *.lnk,*.url,*.appref-ms -Recurse |
                Where-Object { $_.BaseName -like "*$AppName*" } |
                Select-Object -First 1

    if ($null -ne $shortcut) {
        $destination = Join-Path $desktopDir $shortcut.Name
        Copy-Item $shortcut.FullName -Destination $destination -Force
        Write-Host "[OK] Desktop shortcut added for $AppName" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No shortcut found for $AppName" -ForegroundColor Yellow
    }
}

# Ensure winget is available
if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] 'winget' is not available. Attempting to install App Installer..." -ForegroundColor Yellow
    try {
        $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetPath = Join-Path $env:TEMP "AppInstaller.msixbundle"
        if (Download-File -Url $wingetUrl -Path $wingetPath) {
            Add-AppxPackage -Path $wingetPath -ForceApplicationShutdown
            Remove-Item $wingetPath -ErrorAction SilentlyContinue
            Write-Host "[OK] winget installed successfully." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to download winget installer." -ForegroundColor Red
            return
        }
    } catch {
        Write-Host "[ERROR] Failed to install winget automatically: $_" -ForegroundColor Red
        return
    }
}

# Ensure C:\Scripts exists
$scriptFolder = "C:\Scripts"
if (-not (Test-Path $scriptFolder)) {
    New-Item -ItemType Directory -Path $scriptFolder | Out-Null
}

# Install Apps
$apps = @(
    @{ Name = ".NET Desktop Runtime 6"; Id = "Microsoft.DotNet.DesktopRuntime.6" },
    @{ Name = ".NET Desktop Runtime 7"; Id = "Microsoft.DotNet.DesktopRuntime.7" },
    @{ Name = ".NET Desktop Runtime 8"; Id = "Microsoft.DotNet.DesktopRuntime.8" },
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x64)"; Id = "Microsoft.VC++2015-2022Redist-x64" },
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x86)"; Id = "Microsoft.VC++2015-2022Redist-x86" },
    @{ Name = "7-Zip"; Id = "7zip.7zip" },
    @{ Name = "Notepad++"; Id = "Notepad++.Notepad++" },
    @{ Name = "VLC Media Player"; Id = "VideoLAN.VLC" },
    @{ Name = "Telegram"; Id = "Telegram.TelegramDesktop" },
    @{ Name = "Zoom"; Id = "Zoom.Zoom" },
    @{ Name = "Microsoft Teams"; Id = "Microsoft.Teams" },
    @{ Name = "AnyDesk"; Id = "AnyDesk.AnyDesk" },
    @{ Name = "Google Chrome"; Id = "Google.Chrome" },
    @{ Name = "Google Drive"; Id = "Google.GoogleDrive" },
    @{ Name = "LibreOffice"; Id = "TheDocumentFoundation.LibreOffice" },
    @{ Name = "PowerShell 7"; Id = "Microsoft.PowerShell" },
    @{ Name = "Python"; Id = "Python.Python.3.12" },
    @{ Name = "Windows Terminal"; Id = "Microsoft.WindowsTerminal" }
)

# Apps that should not have shortcuts copied to the public desktop
$skipShortcutApps = @('PowerShell 7','Python')

foreach ($app in $apps) {
    Write-Host "[INFO] Installing $($app.Name)..." -ForegroundColor Cyan
    try {
        winget install --id=$($app.Id) --accept-source-agreements --accept-package-agreements -e -h --disable-interactivity --scope machine
        Write-Host "[OK] Installed $($app.Name)" -ForegroundColor Green

        if ($skipShortcutApps -notcontains $app.Name) {
            Add-DesktopShortcut -AppName $app.Name
        } else {
            Write-Host "[INFO] Skipping desktop shortcut for $($app.Name)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "[ERROR] Failed to install $($app.Name): $_" -ForegroundColor Red
    }
}

# Write Update Script
$updateScriptPath = Join-Path $scriptFolder "Update-WingetApps.ps1"
$updateScriptContent = @'
winget upgrade --all --accept-source-agreements --accept-package-agreements --disable-interactivity
'@
Set-Content -Path $updateScriptPath -Value $updateScriptContent -Encoding UTF8

# Schedule Task
$taskName = "Weekly Winget App Update"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updateScriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 8:00am

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Weekly winget updates" -RunLevel Highest -User "SYSTEM"
    Write-Host "[OK] Scheduled weekly update task" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to register scheduled task: $_" -ForegroundColor Red
}

# Download SetUserFTA from setuserfta.com (distributed as ZIP)
$setUserFtaUrl = 'https://setuserfta.com/downloads/SetUserFTA.zip'
$setUserFtaZip  = Join-Path $env:TEMP 'SetUserFTA.zip'
$setUserFtaPath = Join-Path $scriptFolder 'SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "Downloading SetUserFTA..." -ForegroundColor Cyan
    if (Download-File -Url $setUserFtaUrl -Path $setUserFtaZip) {
        try {
            Expand-Archive -Path $setUserFtaZip -DestinationPath $scriptFolder -Force
            Remove-Item $setUserFtaZip -ErrorAction SilentlyContinue
            Write-Host "[OK] SetUserFTA extracted to $setUserFtaPath" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Failed to extract SetUserFTA: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[ERROR] SetUserFTA download failed" -ForegroundColor Red
    }
}
