# Disable Microsoft account sign-in prompts and account creation

# Check if the current profile is associated with a Microsoft account
$identitiesPath = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\StoredIdentities'
$identityFound = Test-Path $identitiesPath

# Determine the domain for the current user. Microsoft accounts show the domain
# value "MicrosoftAccount" instead of the computer name.
$currentUser = Get-CimInstance Win32_UserAccount -Filter "Name='$env:USERNAME'" -ErrorAction SilentlyContinue
$domainIsMicrosoft = $currentUser -and $currentUser.Domain -eq 'MicrosoftAccount'

# Consider the user a Microsoft account if either the registry or domain check matches
$hasMicrosoftAccount = $identityFound -or $domainIsMicrosoft

# Detect if any enabled local accounts exist besides the built-ins
$acctInfo = Get-LocalAccountCount
$filteredAccounts = $acctInfo.Accounts

# Determine whether any extra local accounts exist
$hasLocalAccount = $acctInfo.Count -gt 0

if ($hasMicrosoftAccount) {
    Write-Warning 'A Microsoft account is detected. Disabling it may lock you out.'

    if ($hasLocalAccount) {
        Write-Host 'Local accounts detected:'
        $filteredAccounts | ForEach-Object { Write-Host " - $($_.Name)" }
    }
    else {
        Write-Warning 'No additional local accounts were found.'
        $create = Read-Host 'Would you like to create a local account now? [y/N]'
        if ($create -eq 'y') {
            $username = New-LocalUserAccount -AccountType 'Administrator'
            if ($null -ne $username) { $hasLocalAccount = $true }
        }
    }

    $confirmation = Read-Host 'Disable Microsoft account features? [y/N]'
    if ($confirmation -ne 'y') {
        Write-Host 'Microsoft account changes skipped.'
        return
    }
} else {
    $confirmation = Read-Host 'No Microsoft account detected. Disable Microsoft account features anyway? [y/N]'
    if ($confirmation -ne 'y') {
        Write-Host 'Microsoft account changes skipped.'
        return
    }
}

# Block Microsoft account sign-in prompts
Write-Host 'Blocking Microsoft account sign-in prompts...'
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "NoConnectedUser" -Value 3 -Type "DWord" -Force

# Disable Microsoft account creation
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "BlockUserFromCreatingAccounts" -Value 1 -Type "DWord" -Force

# Disable Microsoft 365 promotional notifications
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0 -Type "DWord" -Force

# Disable Windows Hello for Business sign-in
Write-Host 'Disabling Windows Hello for Business...'
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "Enabled" -Value 0 -Type "DWord" -Force

