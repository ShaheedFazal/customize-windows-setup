# Disable Microsoft account sign-in prompts and account creation

param(
    [switch]$Force
)

# Determine if the current profile is associated with a Microsoft account.
# Microsoft accounts show the domain value "MicrosoftAccount" instead of the computer name.
$currentUser = Get-CimInstance Win32_UserAccount -Filter "Name='$env:USERNAME'" -ErrorAction SilentlyContinue
$hasMicrosoftAccount = $currentUser -and $currentUser.Domain -eq 'MicrosoftAccount'

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
        if (-not $Force) {
            Write-Warning 'Skipping Microsoft account changes to avoid lockout. Use -Force to override.'
            return
        }
    }

    if (-not $Force) {
        Write-Host 'Proceeding to disable Microsoft account features.'
    }
} else {
    if (-not $Force) {
        Write-Host 'No Microsoft account detected. Disabling sign-in features to prevent accidental account addition.'
    } else {
        Write-Host 'No Microsoft account detected, but -Force specified. Disabling features anyway.'
    }
}

# Block Microsoft account sign-in prompts
Write-Host 'Blocking Microsoft account sign-in prompts...'
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "NoConnectedUser" -Value 3 -Type "DWord" -Force

# Disable Microsoft account creation
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "BlockUserFromCreatingAccounts" -Value 1 -Type "DWord" -Force

# Disable Microsoft 365 promotional notifications for all users
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0 -Type "DWord" -Force

# Disable Windows Hello for Business sign-in
Write-Host 'Disabling Windows Hello for Business...'
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "Enabled" -Value 0 -Type "DWord" -Force

