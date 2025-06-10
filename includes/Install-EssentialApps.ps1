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

# Locate a shortcut file for an application
function Find-AppShortcut {
    param([string]$AppName)
    $locations = @(
        "$env:PUBLIC\Desktop",
        "$env:USERPROFILE\Desktop",
        [Environment]::GetFolderPath('CommonPrograms'),
        [Environment]::GetFolderPath('Programs')
    )
    foreach ($loc in $locations) {
        $s = Get-ChildItem -Path $loc -Filter "*$AppName*" -Include *.lnk -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($s) { return $s.FullName }
    }
    return $null
}

# Locate an executable when no shortcut exists
function Find-AppExecutable {
    param([string]$AppName)

    $searchDirs = @(
        Join-Path $env:LOCALAPPDATA 'Programs'
        $env:LOCALAPPDATA
        $env:APPDATA
        $env:ProgramFiles
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($AppName -eq 'Microsoft Teams') {
        $teamsPaths = @(
            Join-Path $env:ProgramFiles 'Microsoft\Teams\current\Teams.exe'
            Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft\Teams\current\Teams.exe'
            Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe'
        )
        foreach ($tp in $teamsPaths) {
            if (Test-Path $tp) {
                if ($tp -like "$env:LOCALAPPDATA*") {
                    Write-Host "[INFO] Detected per-user Teams installation" -ForegroundColor Gray
                } else {
                    Write-Host "[INFO] Detected machine-wide Teams installation" -ForegroundColor Gray
                }
                return $tp
            }
        }
    }

    foreach ($dir in $searchDirs) {
        $exe = Get-ChildItem -Path $dir -Filter "*$AppName*.exe" -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

# Copy a located shortcut to the public desktop
function Add-DesktopShortcut {
    param([string]$AppName)

    $desktopDir  = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $shortcutPath = Find-AppShortcut -AppName $AppName

    if ($shortcutPath) {
        $destination = Join-Path $desktopDir (Split-Path $shortcutPath -Leaf)
        $destItem = Get-Item $destination -ErrorAction SilentlyContinue
        if ($destItem -and ($destItem.FullName -eq (Get-Item $shortcutPath).FullName)) {
            Write-Host "[INFO] Desktop shortcut already in place for $AppName" -ForegroundColor Gray
        } else {
            Copy-Item $shortcutPath -Destination $destination -Force
            Write-Host "[OK] Desktop shortcut added for $AppName" -ForegroundColor Green
        }
    } else {
        $exePath = Find-AppExecutable -AppName $AppName
        if ($exePath) {
            $destination = Join-Path $desktopDir ("$AppName.lnk")
            $shell  = New-Object -ComObject WScript.Shell
            $link   = $shell.CreateShortcut($destination)
            $link.TargetPath  = $exePath
            $link.IconLocation = $exePath
            $link.Save()
            Write-Host "[OK] Desktop shortcut created for $AppName" -ForegroundColor Green
        } else {
            Write-Host "[WARN] No shortcut found for $AppName" -ForegroundColor Yellow
            if ($AppName -eq 'Microsoft Teams') {
                Write-Host "[INFO] Teams may be installed for another user or in a non-standard location" -ForegroundColor Gray
            }
        }
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
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x64)"; Id = "Microsoft.VCRedist.2015+.x64" },
    @{ Name = "Microsoft Visual C++ 2015-2022 Redistributable (x86)"; Id = "Microsoft.VCRedist.2015+.x86" },
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
$skipShortcutApps = @(
    '.NET Desktop Runtime 6',
    '.NET Desktop Runtime 7',
    '.NET Desktop Runtime 8',
    'Microsoft Visual C++ 2015-2022 Redistributable (x64)',
    'Microsoft Visual C++ 2015-2022 Redistributable (x86)',
    'PowerShell 7',
    'Python',
    'Windows Terminal'
)

# Detect system architecture for reliable winget installs
$architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

foreach ($app in $apps) {
    Write-Host "[INFO] Installing $($app.Name)..." -ForegroundColor Cyan

    winget install --id=$($app.Id) --accept-source-agreements --accept-package-agreements -e -h
    $exitCode = $LASTEXITCODE

    switch ($exitCode) {
        0 {
            Write-Host "[OK] Successfully installed $($app.Name)" -ForegroundColor Green
        }
        -1978335189 {
            Write-Host "[OK] $($app.Name) is already installed and up-to-date" -ForegroundColor Green
        }
        -1978335216 {
            Write-Host "[SKIP] $($app.Name) - No compatible installer available for this system" -ForegroundColor Yellow
        }
        -1978335212 {
            Write-Host "[WARN] $($app.Name) - Package ID not found, may need updating" -ForegroundColor Yellow
        }
        default {
            Write-Host "[ERROR] Failed to install $($app.Name) (Exit code: $exitCode)" -ForegroundColor Red
        }
    }

    if (($exitCode -eq 0 -or $exitCode -eq -1978335189) -and ($skipShortcutApps -notcontains $app.Name)) {
        Add-DesktopShortcut -AppName $app.Name
    } elseif ($skipShortcutApps -contains $app.Name) {
        Write-Host "[INFO] Skipping desktop shortcut for $($app.Name)" -ForegroundColor Gray
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
$trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 8:00am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Weekly winget updates" -RunLevel Highest -User "SYSTEM"
    Write-Host "[OK] Scheduled weekly update task" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to register scheduled task: $_" -ForegroundColor Red
}

# Download architecture specific SetUserFTA
$arch        = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$setUserFtaUrl = "https://setuserfta.com/downloads/SetUserFTA_$arch.zip"
$setUserFtaZip  = Join-Path $env:TEMP "SetUserFTA_$arch.zip"
$setUserFtaPath = Join-Path $scriptFolder 'SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "Downloading SetUserFTA..." -ForegroundColor Cyan
    if (Download-File -Url $setUserFtaUrl -Path $setUserFtaZip) {
        try {
            Expand-Archive -Path $setUserFtaZip -DestinationPath $scriptFolder -Force
            Remove-Item $setUserFtaZip -ErrorAction SilentlyContinue

            $executable = Get-ChildItem -Path $scriptFolder -Filter 'SetUserFTA*.exe' -Recurse | Where-Object { $_.Name -match $arch } | Select-Object -First 1
            if (-not $executable) {
                $executable = Get-ChildItem -Path $scriptFolder -Filter 'SetUserFTA*.exe' -Recurse | Select-Object -First 1
            }
            if ($executable) {
                Copy-Item $executable.FullName $setUserFtaPath -Force
                Write-Host "[OK] SetUserFTA extracted to $setUserFtaPath" -ForegroundColor Green
            } else {
                Write-Warning "SetUserFTA executable not found after extraction"
                Write-Log "SetUserFTA executable missing after extraction"
            }
        } catch {
            Write-Host "[ERROR] Failed to extract SetUserFTA: $_" -ForegroundColor Red
            Write-Log "SetUserFTA extraction failed: $_"
        }
    } else {
        Write-Host "[ERROR] SetUserFTA download failed" -ForegroundColor Red
        Write-Log "SetUserFTA download failed from $setUserFtaUrl"
    }
}
