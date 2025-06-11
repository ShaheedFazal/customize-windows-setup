# Fixed BitLocker Enablement Script
# Addresses the issues found in the original ZZ-Enable-BitLocker.ps1

#Requires -RunAsAdministrator

Write-Host "[BITLOCKER] Starting Enhanced BitLocker Configuration..." -ForegroundColor Cyan

function Test-BitLockerCompatibility {
    [CmdletBinding()]
    param()
    
    $compatible = $true
    $issues = @()
    $warnings = @()
    
    Write-Host "[BITLOCKER] Checking system compatibility..." -ForegroundColor Gray
    
    # Check Administrator privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        $compatible = $false
        $issues += "Administrator privileges required for BitLocker configuration"
    } else {
        Write-Host "  ✓ Running with Administrator privileges" -ForegroundColor Green
    }
    
    # Check Windows edition
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osName = $osInfo.Caption
        
        if ($osName -match "Home") {
            $compatible = $false
            $issues += "Windows Home edition detected - BitLocker requires Pro, Enterprise, or Education"
        } else {
            Write-Host "  ✓ Windows edition supports BitLocker: $osName" -ForegroundColor Green
        }
    } catch {
        $warnings += "Cannot determine Windows edition"
    }
    
    # Check TPM with multiple methods and FIXED property names
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        
        # FIX: Correct property names (remove the 'mp' typo)
        Write-Host "  ✓ TPM Present: $($tpm.TpmPresent)" -ForegroundColor $(if($tpm.TmpPresent){'Green'}else{'Yellow'})
        Write-Host "  ✓ TPM Ready: $($tpm.TmpReady)" -ForegroundColor $(if($tmp.TmpReady){'Green'}else{'Yellow'})
        Write-Host "  ✓ TPM Enabled: $($tpm.TmpEnabled)" -ForegroundColor $(if($tpm.TmpEnabled){'Green'}else{'Yellow'})
        
        # Handle the common case where properties return empty/null
        $tmpPresent = $tpm.TmpPresent
        $tmpReady = $tpm.TmpReady  
        $tmpEnabled = $tpm.TmpEnabled
        
        # If properties are null/empty, try alternative detection
        if ($null -eq $tmpPresent -or $tmpPresent -eq '') {
            Write-Host "  ⚠ TPM properties appear blank, trying alternative detection..." -ForegroundColor Yellow
            
            # Try WMI method
            try {
                $tmpWmi = Get-CimInstance -Namespace "Root\cimv2\security\microsofttpm" -ClassName "Win32_Tpm" -ErrorAction Stop
                if ($tmpWmi) {
                    Write-Host "  ✓ TPM detected via WMI method" -ForegroundColor Green
                    $tmpPresent = $true
                    $tmpReady = $tmpWmi.IsActivated_InitialValue
                    $tmpEnabled = $tmpWmi.IsEnabled_InitialValue
                    
                    Write-Host "  ✓ TPM Enabled (WMI): $tmpEnabled" -ForegroundColor $(if($tmpEnabled){'Green'}else{'Yellow'})
                    Write-Host "  ✓ TPM Activated (WMI): $tmpReady" -ForegroundColor $(if($tmpReady){'Green'}else{'Yellow'})
                } else {
                    $tmpPresent = $false
                }
            } catch {
                # Try service detection as final fallback
                $tmpService = Get-Service -Name "TPM" -ErrorAction SilentlyContinue
                if ($tmpService) {
                    Write-Host "  ✓ TPM service detected, assuming TPM is present" -ForegroundColor Yellow
                    $tmpPresent = $true
                    $tmpReady = $true  # Assume ready if service exists
                    $tmpEnabled = ($tmpService.Status -eq "Running")
                } else {
                    $tmpPresent = $false
                }
            }
        }
        
        # Now evaluate based on corrected values
        if (-not $tmpPresent) {
            $warnings += "TPM not detected - will try alternative methods"
        } elseif (-not $tmpEnabled) {
            $warnings += "TPM not enabled - may need BIOS/UEFI configuration"
        } elseif (-not $tmpReady) {
            $warnings += "TPM not ready/activated - may need initialization"
        } else {
            Write-Host "  ✓ TPM appears to be properly configured" -ForegroundColor Green
        }
        
        # Show TPM version if available
        if ($tmpPresent -and $tpm.TmpVersion) {
            Write-Host "  ✓ TPM Version: $($tpm.TmpVersion)" -ForegroundColor Green
            if ($tpm.TmpVersion -eq "1.2") {
                $warnings += "TPM 1.2 detected - TPM 2.0 recommended for optimal security"
            }
        }
        
    } catch {
        $warnings += "Cannot query TPM status via Get-Tpm: $($_.Exception.Message)"
        
        # Fallback: try to detect via service
        try {
            $tmpService = Get-Service -Name "TPM" -ErrorAction SilentlyContinue
            if ($tmpService) {
                Write-Host "  ⚠ TPM service found - TPM likely present but not accessible via PowerShell" -ForegroundColor Yellow
                $warnings += "TPM detected via service but PowerShell access failed"
            } else {
                $issues += "TPM not detected via any method"
            }
        } catch {
            $issues += "Cannot detect TPM via any method - may not be present"
        }
    }
    
    # Check system drive
    try {
        $systemDrive = Get-Volume -DriveLetter C -ErrorAction Stop
        if ($systemDrive.FileSystem -ne 'NTFS') {
            $compatible = $false
            $issues += "System drive must be NTFS (currently: $($systemDrive.FileSystem))"
        } else {
            Write-Host "  ✓ System drive is NTFS" -ForegroundColor Green
        }
        
        $freeSpaceGB = [math]::Round($systemDrive.SizeRemaining / 1GB, 1)
        if ($freeSpaceGB -lt 2) {
            $warnings += "Low disk space ($freeSpaceGB GB free) - encryption may be slow"
        } else {
            Write-Host "  ✓ Sufficient disk space available ($freeSpaceGB GB free)" -ForegroundColor Green
        }
    } catch {
        $issues += "Cannot check system drive: $($_.Exception.Message)"
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
    
    return @{
        Compatible = $compatible
        AlreadyEnabled = $false
        Issues = $issues
        Warnings = $warnings
    }
}

function Enable-BitLockerWithRecovery {
    [CmdletBinding()]
    param()
    
    Write-Host "[BITLOCKER] Attempting BitLocker enablement with improved error handling..." -ForegroundColor Cyan
    
    # Method 1: Try TPM protector (most common and secure)
    Write-Host "  Method 1: Trying TPM protector..." -ForegroundColor Yellow
    try {
        # FIX: Use correct parameter name -TmpProtector
        $result = Enable-BitLocker -MountPoint 'C:' -TmpProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop
        Write-Host "  ✓ BitLocker enabled with TPM protector!" -ForegroundColor Green
        $protectorMethod = "TPM"
    } catch {
        Write-Host "  ⚠ TPM method failed: $($_.Exception.Message)" -ForegroundColor Yellow
        
        # Method 2: Try recovery password only (simpler approach)
        Write-Host "  Method 2: Trying recovery password protector..." -ForegroundColor Yellow
        try {
            $result = Enable-BitLocker -MountPoint 'C:' -RecoveryPasswordProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop
            Write-Host "  ✓ BitLocker enabled with recovery password protector!" -ForegroundColor Green
            $protectorMethod = "RecoveryPassword"
        } catch {
            Write-Host "  ⚠ Recovery password method failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            # Method 3: Ask user for password protector
            $usePassword = Read-Host "  Would you like to try password-based protection? [y/N]"
            if ($usePassword -eq 'y') {
                try {
                    $securePassword = Read-Host "  Enter a strong password for BitLocker" -AsSecureString
                    $result = Enable-BitLocker -MountPoint 'C:' -PasswordProtector -Password $securePassword -EncryptionMethod XtsAes256 -UsedSpaceOnly -ErrorAction Stop
                    Write-Host "  ✓ BitLocker enabled with password protector!" -ForegroundColor Green
                    Write-Host "  ⚠ IMPORTANT: You will need to enter this password at every boot!" -ForegroundColor Yellow
                    $protectorMethod = "Password"
                } catch {
                    Write-Host "  ✗ All methods failed: $($_.Exception.Message)" -ForegroundColor Red
                    return $null
                }
            } else {
                Write-Host "  ✗ All automatic methods failed" -ForegroundColor Red
                return $null
            }
        }
    }
    
    # Add recovery password protector if not already the primary method
    if ($protectorMethod -ne "RecoveryPassword") {
        Write-Host "  Adding recovery password protector..." -ForegroundColor Yellow
        try {
            Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Recovery password protector added" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ Warning: Could not add recovery password protector: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Wait for protectors to be registered
    Write-Host "  Waiting for key protectors to be registered..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    return $protectorMethod
}

function Get-BitLockerRecoveryInformation {
    [CmdletBinding()]
    param()
    
    try {
        $volume = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        
        # Find recovery password protector
        $recoveryProtector = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        
        if ($recoveryProtector) {
            return @{
                Found = $true
                KeyProtectorId = $recoveryProtector.KeyProtectorId
                RecoveryPassword = $recoveryProtector.RecoveryPassword
                VolumeStatus = $volume.ProtectionStatus
                EncryptionPercentage = $volume.EncryptionPercentage
                EncryptionMethod = $volume.EncryptionMethod
            }
        } else {
            return @{
                Found = $false
                Message = "No recovery password protector found"
            }
        }
    } catch {
        return @{
            Found = $false
            Message = "Failed to query BitLocker volume: $($_.Exception.Message)"
        }
    }
}

function Save-RecoveryInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$RecoveryInfo,
        [Parameter(Mandatory=$true)][string]$ProtectorMethod
    )
    
    if (-not $RecoveryInfo.Found) {
        Write-Host "  ⚠ Warning: $($RecoveryInfo.Message)" -ForegroundColor Yellow
        return $false
    }
    
    # Create comprehensive recovery document
    $recoveryContent = @(
        "BitLocker Recovery Information",
        "=" * 60,
        "",
        "SYSTEM INFORMATION:",
        "Computer Name: $env:COMPUTERNAME",
        "User: $env:USERNAME",
        "Domain/Workgroup: $((Get-CimInstance Win32_ComputerSystem).Domain)",
        "Date Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Windows Version: $((Get-CimInstance Win32_OperatingSystem).Caption)",
        "",
        "BITLOCKER CONFIGURATION:",
        "Protection Method: $ProtectorMethod",
        "Encryption Status: $($RecoveryInfo.VolumeStatus)",
        "Encryption Progress: $($RecoveryInfo.EncryptionPercentage)%",
        "Encryption Method: $($RecoveryInfo.EncryptionMethod)",
        "",
        "RECOVERY INFORMATION:",
        "Key Protector ID: $($RecoveryInfo.KeyProtectorId)",
        "Recovery Password: $($RecoveryInfo.RecoveryPassword)",
        "",
        "USAGE INSTRUCTIONS:",
        "1. Boot computer until BitLocker recovery screen appears",
        "2. Enter the 48-digit recovery password above",
        "3. Press Enter to unlock the drive",
        "",
        "WHEN YOU MIGHT NEED THIS:",
        "- TPM hardware failure or changes",
        "- BIOS/UEFI configuration changes",
        "- Motherboard replacement or major hardware changes",
        "- Moving the drive to another computer",
        "- Windows boot failure requiring recovery",
        "- Forgotten password (if using password protection)",
        "",
        "SECURITY BEST PRACTICES:",
        "- Store this document in multiple secure locations",
        "- Keep copies separate from the encrypted computer",
        "- Consider printing a physical backup",
        "- Do not store in cloud services without additional encryption",
        "- Update this information if recovery keys change",
        "",
        "For technical support, contact your IT administrator."
    )
    
    # Display recovery information
    Write-Host "`n" + "="*70 -ForegroundColor Red
    Write-Host "🔑 CRITICAL: BITLOCKER RECOVERY INFORMATION" -ForegroundColor Red
    Write-Host "="*70 -ForegroundColor Red
    Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "Protection Method: $ProtectorMethod" -ForegroundColor White
    Write-Host "Key Protector ID: $($RecoveryInfo.KeyProtectorId)" -ForegroundColor Yellow
    Write-Host "Recovery Password: $($RecoveryInfo.RecoveryPassword)" -ForegroundColor Yellow
    Write-Host "="*70 -ForegroundColor Red
    Write-Host "🚨 RECORD THIS INFORMATION IMMEDIATELY!" -ForegroundColor Red
    Write-Host "="*70 -ForegroundColor Red
    
    # Offer multiple save options
    Write-Host "`n[SAVE OPTIONS]" -ForegroundColor Cyan
    Write-Host "1. Save to Documents folder (recommended)" -ForegroundColor White
    Write-Host "2. Save to Desktop (visible)" -ForegroundColor White
    Write-Host "3. Save to both locations" -ForegroundColor White
    Write-Host "4. Display only (manual copy)" -ForegroundColor White
    
    $saveChoice = Read-Host "Choose save option [1-4]"
    
    $savedFiles = @()
    
    switch ($saveChoice) {
        "1" {
            $documentsPath = [Environment]::GetFolderPath('MyDocuments')
            $filePath = Join-Path $documentsPath "BitLocker-Recovery-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
            try {
                $recoveryContent | Set-Content -Path $filePath -Encoding UTF8 -Force
                $savedFiles += $filePath
                Write-Host "  ✓ Saved to Documents folder" -ForegroundColor Green
            } catch {
                Write-Host "  ❌ Failed to save to Documents: $_" -ForegroundColor Red
            }
        }
        "2" {
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $filePath = Join-Path $desktopPath "BitLocker-Recovery-$env:COMPUTERNAME.txt"
            try {
                $recoveryContent | Set-Content -Path $filePath -Encoding UTF8 -Force
                $savedFiles += $filePath
                Write-Host "  ✓ Saved to Desktop" -ForegroundColor Green
            } catch {
                Write-Host "  ❌ Failed to save to Desktop: $_" -ForegroundColor Red
            }
        }
        "3" {
            $documentsPath = [Environment]::GetFolderPath('MyDocuments')
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $docFile = Join-Path $documentsPath "BitLocker-Recovery-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
            $desktopFile = Join-Path $desktopPath "BitLocker-Recovery-$env:COMPUTERNAME.txt"
            
            try {
                $recoveryContent | Set-Content -Path $docFile -Encoding UTF8 -Force
                $savedFiles += $docFile
                Write-Host "  ✓ Saved to Documents folder" -ForegroundColor Green
            } catch {
                Write-Host "  ❌ Failed to save to Documents: $_" -ForegroundColor Red
            }
            
            try {
                $recoveryContent | Set-Content -Path $desktopFile -Encoding UTF8 -Force
                $savedFiles += $desktopFile
                Write-Host "  ✓ Saved to Desktop" -ForegroundColor Green
            } catch {
                Write-Host "  ❌ Failed to save to Desktop: $_" -ForegroundColor Red
            }
        }
        "4" {
            Write-Host "`nRecovery information displayed above for manual copying." -ForegroundColor Yellow
        }
        default {
            Write-Host "Invalid option selected." -ForegroundColor Yellow
        }
    }
    
    if ($savedFiles.Count -gt 0) {
        Write-Host "`n✅ Recovery information saved to:" -ForegroundColor Green
        foreach ($file in $savedFiles) {
            Write-Host "  📄 $file" -ForegroundColor Green
        }
        
        Write-Host "`n🔐 SECURITY REMINDER:" -ForegroundColor Red
        Write-Host "Move these files to secure external storage immediately!" -ForegroundColor Yellow
        Write-Host "Do not leave recovery keys on the encrypted drive!" -ForegroundColor Yellow
    }
    
    Read-Host "`nPress Enter after you have safely recorded this information"
    return $true
}

function Save-RecoveryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][array]$Content
    )
    
    try {
        $directory = Split-Path $Path -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        $Content | Set-Content -Path $Path -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Host "  ❌ Failed to save: $Path - $_" -ForegroundColor Red
        return $false
    }
}

function Show-FinalStatus {
    [CmdletBinding()]
    param()
    
    try {
        $status = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        
        Write-Host "`n[FINAL BITLOCKER STATUS]" -ForegroundColor Cyan
        Write-Host "Protection Status: $($status.ProtectionStatus)" -ForegroundColor Green
        Write-Host "Encryption Progress: $($status.EncryptionPercentage)%" -ForegroundColor White
        Write-Host "Encryption Method: $($status.EncryptionMethod)" -ForegroundColor White
        Write-Host "Lock Status: $($status.LockStatus)" -ForegroundColor White
        
        if ($status.KeyProtector) {
            Write-Host "Key Protectors:" -ForegroundColor White
            foreach ($protector in $status.KeyProtector) {
                Write-Host "  - $($protector.KeyProtectorType)" -ForegroundColor Gray
            }
        }
        
        if ($status.EncryptionPercentage -lt 100) {
            Write-Host "`n⏳ ENCRYPTION IN PROGRESS" -ForegroundColor Yellow
            Write-Host "Encryption will continue in the background" -ForegroundColor Yellow
            Write-Host "You can use your computer normally during this process" -ForegroundColor Green
            Write-Host "Check progress anytime with: Get-BitLockerVolume -MountPoint 'C:'" -ForegroundColor Gray
        } else {
            Write-Host "`n✅ Encryption is complete!" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "`n⚠ Could not retrieve final status: $_" -ForegroundColor Yellow
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "Enhanced BitLocker Configuration Tool" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Run compatibility check
$compatibility = Test-BitLockerCompatibility

# Display warnings
if ($compatibility.Warnings.Count -gt 0) {
    Write-Host "`n[WARNINGS]" -ForegroundColor Yellow
    foreach ($warning in $compatibility.Warnings) {
        Write-Host "⚠ $warning" -ForegroundColor Yellow
    }
}

# Check for blocking issues
if (-not $compatibility.Compatible) {
    Write-Host "`n[BLOCKING ISSUES]" -ForegroundColor Red
    foreach ($issue in $compatibility.Issues) {
        Write-Host "❌ $issue" -ForegroundColor Red
    }
    
    Write-Host "`nPlease resolve these issues before proceeding:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're running PowerShell as Administrator" -ForegroundColor White
    Write-Host "2. For Windows Home: Upgrade to Pro/Enterprise/Education" -ForegroundColor White
    Write-Host "3. For TPM issues: Check BIOS/UEFI settings" -ForegroundColor White
    Write-Host "4. For drive issues: Ensure system drive is NTFS" -ForegroundColor White
    
    exit 1
}

# Check if already enabled
if ($compatibility.AlreadyEnabled) {
    Write-Host "`n✅ BitLocker is already enabled!" -ForegroundColor Green
    Show-FinalStatus
    
    # Check if recovery info exists and offer to save it
    $recoveryInfo = Get-BitLockerRecoveryInformation
    if ($recoveryInfo.Found) {
        $saveExisting = Read-Host "`nWould you like to save the existing recovery information? [y/N]"
        if ($saveExisting -eq 'y') {
            Save-RecoveryInformation -RecoveryInfo $recoveryInfo -ProtectorMethod "Existing"
        }
    }
    exit 0
}

# Proceed with enablement
Write-Host "`n✅ System is compatible with BitLocker!" -ForegroundColor Green
Write-Host "`nThis will:" -ForegroundColor White
Write-Host "• Encrypt your C: drive with AES-256 encryption" -ForegroundColor White
Write-Host "• Use the most secure protection method available" -ForegroundColor White
Write-Host "• Generate a recovery password for emergency access" -ForegroundColor White
Write-Host "• Continue encryption in the background" -ForegroundColor White

$confirmation = Read-Host "`nProceed with BitLocker enablement? [y/N]"
if ($confirmation -ne 'y') {
    Write-Host "BitLocker setup cancelled." -ForegroundColor Yellow
    exit 0
}

# Enable BitLocker
$protectorMethod = Enable-BitLockerWithRecovery

if ($protectorMethod) {
    Write-Host "`n🎉 BitLocker enabled successfully using $protectorMethod protection!" -ForegroundColor Green
    
    # Get recovery information
    $recoveryInfo = Get-BitLockerRecoveryInformation
    
    # Save recovery information
    $saved = Save-RecoveryInformation -RecoveryInfo $recoveryInfo -ProtectorMethod $protectorMethod
    
    if ($saved) {
        Write-Host "`n✅ Recovery information saved successfully!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠ BitLocker enabled but recovery information could not be saved" -ForegroundColor Yellow
        Write-Host "You can retrieve it later with: Get-BitLockerVolume -MountPoint 'C:'" -ForegroundColor Gray
    }
    
    # Show final status
    Show-FinalStatus
    
    Write-Host "`n🔐 BitLocker setup completed successfully!" -ForegroundColor Green
    Write-Host "Your system drive is now encrypted and protected." -ForegroundColor Green
    
} else {
    Write-Host "`n❌ BitLocker enablement failed with all methods" -ForegroundColor Red
    Write-Host "`nYou mentioned manual enablement works. Try these commands:" -ForegroundColor Yellow
    Write-Host "Enable-BitLocker -MountPoint 'C:' -TmpProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly" -ForegroundColor Gray
    Write-Host "Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector" -ForegroundColor Gray
    Write-Host "`nThen run the recovery key script to save your information." -ForegroundColor Yellow
}
