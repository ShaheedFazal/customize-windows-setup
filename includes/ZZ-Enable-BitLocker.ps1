# Check if BitLocker is enabled
$bitlockerStatus = Get-BitLockerVolume -MountPoint "C:"

if ($bitlockerStatus.ProtectionStatus -eq 'Off') {
    Write-Host "🔐 Enabling BitLocker on C: drive..."

    # Enable BitLocker using TPM and create a recovery password
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TpmProtector -RecoveryPasswordProtector -UsedSpaceOnly

    # Retrieve the generated recovery password
    $recoveryPassword = (Get-BitLockerVolume -MountPoint "C:").KeyProtector |
        Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } |
        Select-Object -ExpandProperty RecoveryPassword

    # Save recovery info with computer details
    $keyPath = "C:\BitLockerRecoveryKey.txt"
    $info = @(
        "ComputerName: $env:COMPUTERNAME",
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "RecoveryPassword: $recoveryPassword"
    )
    $info | Out-File -FilePath $keyPath -Encoding UTF8

    Write-Host "✅ BitLocker enabled. Recovery info saved to $keyPath"
} else {
    Write-Host "🔒 BitLocker is already enabled on the system drive."
}
