# Remove OneDrive - Comprehensive removal with fallback disable

Write-Host "[INFO] Starting OneDrive removal process..." -ForegroundColor Cyan

# Check if OneDrive is actually installed
$onedriveInstalled = $false
$onedrivePaths = @(
    "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe",
    "$env:SYSTEMROOT\System32\OneDriveSetup.exe"
)

foreach ($path in $onedrivePaths) {
    if (Test-Path $path) {
        $onedriveInstalled = $true
        $onedriveSetup = $path
        break
    }
}

if ($onedriveInstalled) {
    Write-Host "[INFO] OneDrive installation detected - attempting full uninstall..."
    
    # Stop OneDrive processes
    Get-Process -Name "OneDrive*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Run the official uninstaller
    try {
        Start-Process $onedriveSetup "/uninstall" -NoNewWindow -Wait -ErrorAction Stop
        Write-Host "[OK] OneDrive uninstaller completed" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] OneDrive uninstaller failed: $_" -ForegroundColor Yellow
    }

    # Stop explorer to clean up shell integration
    Get-Process -Name "explorer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2


    # Clean up OneDrive folders for every user profile
    $profileRoot = Join-Path $env:SystemDrive 'Users'
    $profiles = Get-ChildItem -Path $profileRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') }

    foreach ($profile in $profiles) {
        $oneDriveDir = Join-Path $profile.FullName 'OneDrive'
        $appDataDir  = Join-Path $profile.FullName 'AppData\Local\Microsoft\OneDrive'

        if (Test-Path $oneDriveDir) {
            $docsDir = Join-Path $profile.FullName 'Documents'
            if (!(Test-Path $docsDir)) {
                New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
            }
            try {
                Get-ChildItem -Path $oneDriveDir -Force | ForEach-Object {
                    Move-Item -Path $_.FullName -Destination $docsDir -Force -ErrorAction Stop
                }
                Write-Host "[OK] Moved files from $oneDriveDir to $docsDir" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Failed to move files from $oneDriveDir - $_" -ForegroundColor Yellow
            }
        }

        $userFolders = @($oneDriveDir, $appDataDir)

        foreach ($folder in $userFolders) {
            if (Test-Path $folder) {
                try {
                    Remove-Item -Path $folder -Force -Recurse -ErrorAction Stop
                    Write-Host "[OK] Removed folder: $folder" -ForegroundColor Green
                } catch {
                    Write-Host "[WARN] Could not remove folder: $folder - $_" -ForegroundColor Yellow
                }
            }
        }
    }
    $commonFolders = @(
        "$env:PROGRAMDATA\Microsoft OneDrive",
        "$env:SYSTEMDRIVE\OneDriveTemp"
    )

    foreach ($folder in $commonFolders) {
        if (Test-Path $folder) {
            try {
                Remove-Item -Path $folder -Force -Recurse -ErrorAction Stop
                Write-Host "[OK] Removed folder: $folder" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Could not remove folder: $folder - $_" -ForegroundColor Yellow
            }
        }
    }

    # Remove Start Menu shortcuts created by OneDrive
    Write-Host "[INFO] Cleaning up OneDrive Start Menu shortcuts..."

    $commonStartMenu = Join-Path $env:ProgramData 'Microsoft\\Windows\\Start Menu\\Programs'
    if (Test-Path $commonStartMenu) {
        Get-ChildItem -Path $commonStartMenu -Filter 'OneDrive*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                Write-Host "[OK] Removed shortcut: $($_.FullName)" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Could not remove shortcut: $($_.FullName) - $_" -ForegroundColor Yellow
            }
        }
    }

    foreach ($profile in $profiles) {
        $userStartMenu = Join-Path $profile.FullName 'AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs'
        if (Test-Path $userStartMenu) {
            Get-ChildItem -Path $userStartMenu -Filter 'OneDrive*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Host "[OK] Removed user shortcut: $($_.FullName)" -ForegroundColor Green
                } catch {
                    Write-Host "[WARN] Could not remove user shortcut: $($_.FullName) - $_" -ForegroundColor Yellow
                }
            }
        }
    }

    # Clean up registry shell extensions
    if (-not (Get-PSDrive -Name "HKCR" -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
    }

    $registryKeysToRemove = @(
        "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
        "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    )

    foreach ($regKey in $registryKeysToRemove) {
        if (Test-Path $regKey) {
            Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Restart Explorer
    Start-Process "explorer.exe" -ErrorAction SilentlyContinue
    Write-Host "[OK] OneDrive uninstalled successfully" -ForegroundColor Green
    
} else {
    Write-Host "[INFO] OneDrive not installed - applying policy disable as fallback..."
}

# Apply policy disable (works whether OneDrive is installed or not)
# This prevents OneDrive from being reinstalled via Windows Updates or Consumer Features
Write-Host "[INFO] Applying OneDrive disable policy..."
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Type DWord -Value 1

Write-Host "[DONE] OneDrive removal and policy disable completed" -ForegroundColor Green
