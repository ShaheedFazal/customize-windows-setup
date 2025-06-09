## Create standard user account

$confirm = Read-Host 'Create a new standard user account? [y/N]'
if ($confirm -ne 'y') {
    Write-Host 'User creation cancelled.'
    return
}

$username = Read-Host 'Enter a user name for the standard account'
do {
    $pw1 = Read-Host 'Enter password' -AsSecureString
    $pw2 = Read-Host 'Confirm password' -AsSecureString
    if ([System.Net.NetworkCredential]::new('', $pw1).Password -ne [System.Net.NetworkCredential]::new('', $pw2).Password) {
        Write-Warning 'Passwords do not match. Please try again.'
    }
} until ([System.Net.NetworkCredential]::new('', $pw1).Password -eq [System.Net.NetworkCredential]::new('', $pw2).Password)

New-LocalUserAccount -Username $username -Password $pw1 -Groups @('Users')

Write-Host "Created standard user account '$username'."
