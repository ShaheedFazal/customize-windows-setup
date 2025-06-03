# Check if BitLocker is enabled
$bitlockerStatus = Get-BitLockerVolume -MountPoint "C:"

if ($bitlockerStatus.ProtectionStatus -eq 'Off') {
    Write-Host "🔐 Enabling BitLocker on C: drive..."

    # Enable BitLocker using TPM and back up recovery key to a file
    $keyPath = "C:\BitLockerRecoveryKey.txt"
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TpmProtector -RecoveryPasswordProtector -RecoveryKeyPath "C:\" -UsedSpaceOnly

    Write-Host "✅ BitLocker enabled. Recovery key saved to $keyPath"
} else {
    Write-Host "🔒 BitLocker is already enabled on the system drive."
}
