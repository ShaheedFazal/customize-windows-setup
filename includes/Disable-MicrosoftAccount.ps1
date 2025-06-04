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
$localAccounts = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=true AND Disabled=false" -ErrorAction SilentlyContinue
$filteredAccounts = $localAccounts | Where-Object {
    $_.Name -notin @('Administrator','DefaultAccount','Guest','WDAGUtilityAccount')
}

# Determine whether any extra local accounts exist
$hasLocalAccount = ($filteredAccounts | Measure-Object).Count -gt 0

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
            $username = Read-Host 'Enter a user name for the new account'
            do {
                $pw1 = Read-Host 'Enter password'
                $pw2 = Read-Host 'Confirm password'
                if ($pw1 -ne $pw2) {
                    Write-Warning 'Passwords do not match. Please try again.'
                }
            } until ($pw1 -eq $pw2)
            net user $username $pw1 /add
            net localgroup Administrators $username /add
            Write-Host "Created local administrator account '$username'."
            $hasLocalAccount = $true
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
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 3 /f

# Disable Microsoft account creation
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 1 /f

# Disable Microsoft 365 promotional notifications
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f

# Disable Windows Hello for Business sign-in
Write-Host 'Disabling Windows Hello for Business...'
reg add "HKLM\SOFTWARE\Policies\Microsoft\PassportForWork" /v Enabled /t REG_DWORD /d 0 /f
