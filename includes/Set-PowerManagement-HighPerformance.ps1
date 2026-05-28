# Set Power Management to High Performance with 30-minute display timeout for security
# Note: Use either this script or Disable-Display-Sleep-Mode-Timeouts.ps1, not both, as they could conflict.

Write-Host "Configuring High Performance power plan with screen lock..." -ForegroundColor Cyan

Try {
    # Get High Performance plan GUID. On Win11 Home / certain SKUs the plan
    # isn't pre-installed; we duplicate from the well-known builtin GUID if so.
    $builtinHighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $highPerf = powercfg -l | ForEach-Object { if ($_.contains($POWERMANAGEMENT)) { $_.split()[3] } } | Select-Object -First 1
    if (-not $highPerf) {
        Write-Host "[POWER] High Performance plan not present; creating from builtin..." -ForegroundColor Yellow
        $dup = powercfg -duplicatescheme $builtinHighPerf 2>&1
        if ($dup -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $highPerf = $matches[1]
        }
    }
    if (-not $highPerf) {
        Write-Warning "Could not locate or create a High Performance plan. Skipping plan switch."
    } else {
        $currPlan = $(powercfg -getactivescheme).split()[3]
        if ($currPlan -ne $highPerf) {
            powercfg -setactive $highPerf
            Write-Host "[POWER] Switched to High Performance plan" -ForegroundColor Green
        } else {
            Write-Host "[POWER] Already using High Performance plan" -ForegroundColor Gray
        }
    }
    
    # Get the active scheme GUID for modification
    $currentSchemeOutput = powercfg /getactivescheme
    if ($currentSchemeOutput -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
        $currentGuid = $matches[1]
        
        Write-Host "[POWER] Configuring High Performance plan with security timeout..." -ForegroundColor Yellow
        
        # Set display timeout to 30 minutes while keeping everything else high performance
        powercfg /setacvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 1800
        powercfg /setdcvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 1800
        
        # Ensure disk, system sleep, and hibernate stay disabled (High Performance behavior)
        powercfg /setacvalueindex $currentGuid SUB_DISK DISKIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_DISK DISKIDLE 0
        powercfg /setacvalueindex $currentGuid SUB_SLEEP STANDBYIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_SLEEP STANDBYIDLE 0
        powercfg /setacvalueindex $currentGuid SUB_SLEEP HIBERNATEIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_SLEEP HIBERNATEIDLE 0
        
        # Apply the changes
        powercfg /setactive $currentGuid
        
        Write-Host "[POWER] High Performance configured: Maximum CPU/disk performance + 30min display timeout" -ForegroundColor Green
    }
    
    # Configure lock screen timeout and password requirement
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -Value 1800 -Type "DWord" -Force
    
    # Set screensaver policies for additional security
    $desktopPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveTimeOut" -Value "1800" -Type "String" -Force
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force
    
    # User-level settings
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "1800" -Type "String" -Force
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force
    
    Write-Host "[SECURITY] Screen lock enabled: Display turns off + password required after 30 minutes" -ForegroundColor Green
    
} Catch {
    Write-Warning -Message "Unable to configure power plan: $_" -foregroundcolor $FOREGROUNDCOLOR
}
