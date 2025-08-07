# Enable Num Lock by default for all users
$initialValue = '2'
$policyPath   = 'HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\Keyboard'

if (Test-Path $policyPath) {
    # Enforce via policy and remove per-user overrides
    Set-RegistryValue -Path $policyPath -Name 'InitialKeyboardIndicators' -Value $initialValue -Type 'String' -Force

    Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -notmatch '_Classes$' } | ForEach-Object {
        $path = "Registry::HKEY_USERS\$($_.PSChildName)\Control Panel\Keyboard"
        Remove-RegistryValue -Path $path -Name 'InitialKeyboardIndicators'
    }
} else {
    # Apply to all loaded user hives under HKEY_USERS
    Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -notmatch '_Classes$' } | ForEach-Object {
        $path = "Registry::HKEY_USERS\$($_.PSChildName)\Control Panel\Keyboard"
        Set-RegistryValue -Path $path -Name 'InitialKeyboardIndicators' -Value $initialValue -Type 'String' -Force
    }
}
