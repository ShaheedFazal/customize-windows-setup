# Enhanced BitLocker Configuration Script
# File: includes/ZZ-Enable-BitLocker.ps1

Write-Host "[BITLOCKER] Starting BitLocker configuration..." -ForegroundColor Cyan

function Test-BitLockerCompatibility {
    [CmdletBinding()]
    param()
    
    $compatible = $true
    $issues = @()
    $warnings = @()
    
    Write-Host "[BITLOCKER] Checking system compatibility..." -ForegroundColor Gray
    
    # Check TPM
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if (-not $tpm.TpmPresent) {
            $compatible = $false
            $issues += "TPM not present - BitLocker requires TPM 1.2 or 2.0"
        } elseif (-not $tpm.TpmReady) {
            $compatible = $false
            $issues += "TPM not ready (may require BIOS/UEFI configuration)"
        } elseif (-not $tpm.TpmEnabled) {
            $compatible = $false
            $issues += "TPM not enabled in BIOS/UEFI settings"
        } else {
            Write-Host "  ✓ TPM $($tpm.TpmVersion) detected and ready" -ForegroundColor Green
        }
        
        # Additional TPM checks
        if ($tpm.TpmPresent -and $tpm.TpmReady) {
            if ($tpm.TpmVersion -eq "1.2") {
                $warnings += "TPM 1.2 detected - TPM 2.0 recommended for best security"
            }
        }
    } catch {
        $compatible = $false
        $issues += "Cannot query TPM status: $($_.Exception.Message)"
    }
    
    # Check if system drive is NTFS
    try {
        $systemDrive = Get-Volume -DriveLetter C -ErrorAction Stop
        if ($systemDrive.FileSystem -ne 'NTFS') {
            $compatible = $false
            $issues += "System drive must be NTFS (currently: $($systemDrive.FileSystem))"
        } else {
            Write-Host "  ✓ System drive is NTFS" -ForegroundColor Green
        }
    } catch {
        $issues += "Cannot check system drive file system: $($_.Exception.Message)"
    }
    
    # Check available disk space
    try {
        $systemDrive = Get-Volume -DriveLetter C -ErrorAction Stop
        $freeSpaceGB = [math]::Round($systemDrive.SizeRemaining / 1GB, 1)
        if ($freeSpaceGB -lt 2) {
            $warnings += "Low disk space ($freeSpaceGB GB free) - encryption may be slow"
        } else {
            Write-Host "  ✓ Sufficient disk space available ($freeSpaceGB GB free)" -ForegroundColor Green
        }
    } catch {
        $warnings += "Cannot check disk space"
    }
    
    # Check if already encrypted
    try {
        $bitlockerStatus = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        if ($bitlockerStatus.ProtectionStatus -ne 'Off') {
            Write-Host "  ℹ BitLocker already enabled (Status: $($bitlockerStatus.ProtectionStatus))" -ForegroundColor Blue
            return @{ 
                Compatible = $true
                AlreadyEnabled = $true
                Status = $bitlockerStatus.ProtectionStatus
                EncryptionPercentage = $bitlockerStatus.EncryptionPercentage
                Issues = @()
                Warnings = $warnings
            }
        } else {
            Write-Host "  ✓ BitLocker not currently enabled" -ForegroundColor Green
        }
    } catch {
        $issues += "Cannot check current BitLocker status: $($_.Exception.Message)"
    }
    
    # Check Windows edition compatibility
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osName = $osInfo.Caption
        
        # BitLocker is available on Pro, Enterprise, Education editions
        if ($osName -match "Home") {
            $compatible = $false
            $issues += "Windows Home edition detected - BitLocker requires Pro, Enterprise, or Education"
        } else {
            Write-Host "  ✓ Windows edition supports BitLocker" -ForegroundColor Green
        }
    } catch {
        $warnings += "Cannot determine Windows edition"
    }
    
    # Check if running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        $compatible = $false
        $issues += "Administrator privileges required for BitLocker configuration"
    } else {
        Write-Host "  ✓ Running with Administrator privileges" -ForegroundColor Green
    }
    
    return @{
        Compatible = $compatible
        AlreadyEnabled = $false
        Issues = $issues
        Warnings = $warnings
    }
}

function Enable-BitLockerWithBackup {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "[BITLOCKER] Enabling BitLocker encryption..." -ForegroundColor Cyan
        
        # Enable BitLocker using TPM only and encrypt used space
        Enable-BitLocker -MountPoint 'C:' -TpmProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop
        Write-Host "  ✓ BitLocker enabled with TPM protection" -ForegroundColor Green
        
        # Add a recovery password protector
        Write-Host "[BITLOCKER] Adding recovery password protector..." -ForegroundColor Gray
        Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Recovery password protector added" -ForegroundColor Green
        
        # Retrieve the generated recovery password
        $recoveryPassword = (Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
            Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
            Select-Object -ExpandProperty RecoveryPassword -First 1
        
        if (-not $recoveryPassword) {
            throw "Failed to retrieve recovery password"
        }
        
        # Create recovery information
        $recoveryInfo = @(
            "BitLocker Recovery Information",
            "=" * 40,
            "",
            "Computer Name: $env:COMPUTERNAME",
            "User: $env:USERNAME",
            "Date Encrypted: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "Encryption Method: XTS-AES 256",
            "Key Protector: TPM + Recovery Password",
            "",
            "RECOVERY PASSWORD:",
            $recoveryPassword,
            "",
            "IMPORTANT RECOVERY INSTRUCTIONS:",
            "1. Store this information in a safe location separate from this computer",
            "2. You will need this password if:",
            "   - TPM chip fails or is disabled",
            "   - Motherboard is replaced",
            "   - Hard drive is moved to another computer",
            "   - BIOS/UEFI settings are changed",
            "   - Windows fails to boot normally",
            "",
            "3. To use the recovery password:",
            "   - Boot the computer until you see the BitLocker recovery screen",
            "   - Enter the 48-digit recovery password when prompted",
            "   - Press Enter to unlock the drive",
            "",
            "4. For additional help, contact your IT administrator or visit:",
            "   https://support.microsoft.com/en-us/help/4026181"
        )
        
        # Security-conscious recovery key handling
        Write-Host "`n[SECURITY] Recovery Key Management Options:" -ForegroundColor Yellow
        Write-Host "1. Display on screen only (most secure - you copy manually)" -ForegroundColor White
        Write-Host "2. Save to Documents folder (moderate security)" -ForegroundColor White
        Write-Host "3. Print to default printer (if available)" -ForegroundColor White
        Write-Host "4. Skip saving (show password only)" -ForegroundColor White
        
        $saveChoice = Read-Host "Choose option [1-4]"
        
        switch ($saveChoice) {
            "1" {
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "BITLOCKER RECOVERY PASSWORD - COPY THIS MANUALLY" -ForegroundColor Red
                Write-Host "="*60 -ForegroundColor Cyan
                Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
                Write-Host "Password: $recoveryPassword" -ForegroundColor Yellow
                Write-Host "="*60 -ForegroundColor Cyan
                Write-Host "Store this in a secure location away from this computer!" -ForegroundColor Red
                Read-Host "Press Enter after you have safely recorded this password"
            }
            "2" {
                $documents = [Environment]::GetFolderPath('MyDocuments')
                $keyFileName = "BitLocker-Recovery-$env:COMPUTERNAME.txt"
                $savePath = Join-Path $documents $keyFileName
                
                try {
                    $recoveryInfo | Set-Content -Path $savePath -Encoding UTF8 -ErrorAction Stop
                    Write-Host "  ✓ Recovery information saved: $savePath" -ForegroundColor Green
                    Write-Host "  ⚠ IMPORTANT: Move this file to secure external storage!" -ForegroundColor Yellow
                    Write-Host "  ⚠ Delete the local copy after backing up externally!" -ForegroundColor Yellow
                } catch {
                    Write-Host "  ✗ Could not save file: $_" -ForegroundColor Red
                    Write-Host "  Recovery Password: $recoveryPassword" -ForegroundColor Yellow
                }
            }
            "3" {
                try {
                    $recoveryInfo | Out-Printer -ErrorAction Stop
                    Write-Host "  ✓ Recovery information sent to printer" -ForegroundColor Green
                    Write-Host "  ⚠ Ensure printer output is secured immediately!" -ForegroundColor Yellow
                } catch {
                    Write-Host "  ✗ Could not print: $_" -ForegroundColor Red
                    Write-Host "  Recovery Password: $recoveryPassword" -ForegroundColor Yellow
                }
            }
            default {
                Write-Host "`n[RECOVERY PASSWORD]" -ForegroundColor Red
                Write-Host "$recoveryPassword" -ForegroundColor Yellow
                Write-Host "Please record this password in a secure location!" -ForegroundColor Red
                Read-Host "Press Enter to continue"
            }
        }
        
        # Display status
        $status = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        if ($status) {
            Write-Host "[BITLOCKER] Current Status:" -ForegroundColor Cyan
            Write-Host "  Protection Status: $($status.ProtectionStatus)" -ForegroundColor White
            Write-Host "  Encryption Method: $($status.EncryptionMethod)" -ForegroundColor White
            Write-Host "  Encryption Progress: $($status.EncryptionPercentage)%" -ForegroundColor White
            
            if ($status.EncryptionPercentage -lt 100) {
                Write-Host "  ℹ Encryption will continue in the background" -ForegroundColor Blue
                Write-Host "  ℹ Computer performance may be slightly affected during encryption" -ForegroundColor Blue
            }
        }
        
        return $true
        
    } catch {
        Write-Host "[BITLOCKER ERROR] Failed to enable BitLocker: $_" -ForegroundColor Red
        
        # Attempt to get more specific error information
        try {
            $lastError = Get-WinEvent -FilterHashtable @{LogName='System'; ID=24577} -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($lastError) {
                Write-Host "  System Event: $($lastError.Message)" -ForegroundColor Red
            }
        } catch {
            # Ignore if we can't get system events
        }
        
        return $false
    }
}

function Show-BitLockerStatus {
    [CmdletBinding()]
    param()
    
    try {
        $status = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        
        Write-Host "[BITLOCKER] Current BitLocker Status:" -ForegroundColor Cyan
        Write-Host "  Volume: $($status.MountPoint)" -ForegroundColor White
        Write-Host "  Protection Status: $($status.ProtectionStatus)" -ForegroundColor White
        Write-Host "  Lock Status: $($status.LockStatus)" -ForegroundColor White
        Write-Host "  Encryption Method: $($status.EncryptionMethod)" -ForegroundColor White
        Write-Host "  Encryption Progress: $($status.EncryptionPercentage)%" -ForegroundColor White
        Write-Host "  Volume Type: $($status.VolumeType)" -ForegroundColor White
        
        # Show key protectors
        if ($status.KeyProtector) {
            Write-Host "  Key Protectors:" -ForegroundColor White
            foreach ($protector in $status.KeyProtector) {
                Write-Host "    - $($protector.KeyProtectorType)" -ForegroundColor Gray
            }
        }
        
    } catch {
        Write-Host "[BITLOCKER] Could not retrieve BitLocker status: $_" -ForegroundColor Yellow
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Run compatibility check
$compatibility = Test-BitLockerCompatibility

if (-not $compatibility.Compatible) {
    Write-Host "[BITLOCKER] System is not compatible with BitLocker:" -ForegroundColor Red
    foreach ($issue in $compatibility.Issues) {
        Write-Host "  ✗ $issue" -ForegroundColor Red
    }
    
    Write-Host "`n[BITLOCKER] To resolve these issues:" -ForegroundColor Yellow
    Write-Host "  1. Enable TPM in BIOS/UEFI settings" -ForegroundColor Yellow
    Write-Host "  2. Ensure Windows Pro/Enterprise/Education edition" -ForegroundColor Yellow
    Write-Host "  3. Run as Administrator" -ForegroundColor Yellow
    Write-Host "  4. Ensure system drive is NTFS" -ForegroundColor Yellow
    
    return
}

# Display warnings if any
if ($compatibility.Warnings) {
    Write-Host "[BITLOCKER] Warnings:" -ForegroundColor Yellow
    foreach ($warning in $compatibility.Warnings) {
        Write-Host "  ⚠ $warning" -ForegroundColor Yellow
    }
}

# Check if already enabled
if ($compatibility.AlreadyEnabled) {
    Write-Host "[BITLOCKER] BitLocker is already enabled on this system" -ForegroundColor Green
    Show-BitLockerStatus
    
    # Check if recovery key exists (only check Documents - most secure location)
    $keyFileName = "BitLocker-Recovery-$env:COMPUTERNAME.txt"
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $keyPath = Join-Path $documents $keyFileName
    
    if (Test-Path $keyPath) {
        Write-Host "  ⚠ Found existing recovery key file: $keyPath" -ForegroundColor Yellow
        Write-Host "  ⚠ For security, consider moving this to external secure storage" -ForegroundColor Yellow
    }
    
    return
}

# Prompt user for confirmation
Write-Host "`n[BITLOCKER] Ready to enable BitLocker encryption" -ForegroundColor Cyan
Write-Host "This will:" -ForegroundColor White
Write-Host "  • Encrypt the entire C: drive with AES-256 encryption" -ForegroundColor White
Write-Host "  • Use TPM for automatic unlocking" -ForegroundColor White
Write-Host "  • Generate a recovery password for emergency access" -ForegroundColor White
Write-Host "  • Save recovery information to your Documents folder" -ForegroundColor White
Write-Host "  • Continue encryption in the background after completion" -ForegroundColor White

$confirmation = Read-Host "`nEnable BitLocker encryption? [y/N]"
if ($confirmation -ne 'y') {
    Write-Host "[BITLOCKER] BitLocker configuration cancelled by user" -ForegroundColor Yellow
    return
}

# Enable BitLocker
$success = Enable-BitLockerWithBackup

if ($success) {
    Write-Host "`n[BITLOCKER] ✓ BitLocker has been successfully enabled!" -ForegroundColor Green
    Write-Host "`nIMPORTANT SECURITY REMINDERS:" -ForegroundColor Red
    Write-Host "1. Store recovery password in a secure location SEPARATE from this computer" -ForegroundColor Yellow
    Write-Host "2. Consider using a password manager or secure cloud storage" -ForegroundColor Yellow
    Write-Host "3. DO NOT leave recovery keys on the encrypted drive itself" -ForegroundColor Yellow
    Write-Host "4. Test recovery process on a non-critical system first" -ForegroundColor Yellow
    Write-Host "5. Keep multiple copies in different secure locations" -ForegroundColor Yellow
    Write-Host "6. If you saved to Documents, move to external storage immediately" -ForegroundColor Yellow
    
    # Show final status
    Write-Host ""
    Show-BitLockerStatus
    
} else {
    Write-Host "`n[BITLOCKER] ✗ Failed to enable BitLocker" -ForegroundColor Red
    Write-Host "Check the error messages above for troubleshooting information" -ForegroundColor Red
}
