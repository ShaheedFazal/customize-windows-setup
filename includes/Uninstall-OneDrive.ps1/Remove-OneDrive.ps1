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

    # Clean up OneDrive folders
    $foldersToRemove = @(
        "$env:USERPROFILE\OneDrive",
        "$env:LOCALAPPDATA\Microsoft\OneDrive", 
        "$env:PROGRAMDATA\Microsoft OneDrive",
        "$env:SYSTEMDRIVE\OneDriveTemp"
    )

    foreach ($folder in $foldersToRemove) {
        if (Test-Path $folder) {
            try {
                Remove-Item -Path $folder -Force -Recurse -ErrorAction Stop
                Write-Host "[OK] Removed folder: $folder" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Could not remove folder: $folder - $_" -ForegroundColor Yellow
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
