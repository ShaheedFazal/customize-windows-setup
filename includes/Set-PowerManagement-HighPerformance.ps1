# Set Power Management to High Performance with 15-minute display timeout for security
# Note: Use either this script or Disable-Display-Sleep-Mode-Timeouts.ps1, not both, as they could conflict.

Write-Host "Configuring High Performance power plan with screen lock..." -ForegroundColor Cyan

Try {
    # Get High Performance plan GUID
    $highPerf = powercfg -l | ForEach-Object{if($_.contains($POWERMANAGEMENT)) {$_.split()[3]}}
    $currPlan = $(powercfg -getactivescheme).split()[3]
    
    # Switch to High Performance if not already active
    if ($currPlan -ne $highPerf) {
        powercfg -setactive $highPerf
        Write-Host "[POWER] Switched to High Performance plan" -ForegroundColor Green
    } else {
        Write-Host "[POWER] Already using High Performance plan" -ForegroundColor Gray
    }
    
    # Get the active scheme GUID for modification
    $currentSchemeOutput = powercfg /getactivescheme
    if ($currentSchemeOutput -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
        $currentGuid = $matches[1]
        
        Write-Host "[POWER] Configuring High Performance plan with security timeout..." -ForegroundColor Yellow
        
        # Set display timeout to 15 minutes while keeping everything else high performance
        powercfg /setacvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 900
        powercfg /setdcvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 900
        
        # Ensure disk, system sleep, and hibernate stay disabled (High Performance behavior)
        powercfg /setacvalueindex $currentGuid SUB_DISK DISKIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_DISK DISKIDLE 0
        powercfg /setacvalueindex $currentGuid SUB_SLEEP STANDBYIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_SLEEP STANDBYIDLE 0
        powercfg /setacvalueindex $currentGuid SUB_SLEEP HIBERNATEIDLE 0
        powercfg /setdcvalueindex $currentGuid SUB_SLEEP HIBERNATEIDLE 0
        
        # Apply the changes
        powercfg /setactive $currentGuid
        
        Write-Host "[POWER] ✅ High Performance configured: Maximum CPU/disk performance + 15min display timeout" -ForegroundColor Green
    }
    
    # Configure lock screen timeout and password requirement
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -Value 900 -Type "DWord" -Force
    
    # Set screensaver policies for additional security
    $desktopPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaveTimeOut" -Value "900" -Type "String" -Force
    Set-RegistryValue -Path $desktopPolicy -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force
    
    # User-level settings
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "900" -Type "String" -Force
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1" -Type "String" -Force
    
    Write-Host "[SECURITY] ✅ Screen lock enabled: Display turns off + password required after 15 minutes" -ForegroundColor Green
    
} Catch {
    Write-Warning -Message "Unable to configure power plan: $_" -foregroundcolor $FOREGROUNDCOLOR
}
