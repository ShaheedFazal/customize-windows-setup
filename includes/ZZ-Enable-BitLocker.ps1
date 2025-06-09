$tpm = $null
try {
    $tpm = Get-Tpm
} catch {
    Write-Warning "Failed to query TPM status: $_"
    return
}

if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) {
    Write-Warning "TPM not present or not ready. Skipping BitLocker configuration."
    return
}

# Check if BitLocker is enabled
$bitlockerStatus = Get-BitLockerVolume -MountPoint 'C:'

if ($bitlockerStatus.ProtectionStatus -eq 'Off') {
    Write-Host '[INFO] Enabling BitLocker on C: drive...'

    # Enable BitLocker using TPM only and encrypt used space
    Enable-BitLocker -MountPoint 'C:' -TpmProtector -EncryptionMethod XtsAes256 -UsedSpaceOnly

    # Add a recovery password protector
    Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector | Out-Null

    # Retrieve the generated recovery password
    $recoveryPassword = (Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
        Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
        Select-Object -ExpandProperty RecoveryPassword

    # Save recovery info inside the user's Documents folder with the
    # computer name appended to the file name
    $documents = Join-Path $env:USERPROFILE 'Documents'
    $keyFile  = "BitLockerRecoveryKey-$env:COMPUTERNAME.txt"
    $keyPath  = Join-Path $documents $keyFile

    $info = @(
        "ComputerName: $env:COMPUTERNAME",
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "RecoveryPassword: $recoveryPassword"
    )
    $info | Set-Content -Path $keyPath -Encoding UTF8

    Write-Host "[OK] BitLocker enabled. Recovery info saved to $keyPath"
} else {
    Write-Host "[INFO] BitLocker is already enabled on the system drive."
}
