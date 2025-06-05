## Create standard user account

$username = Read-Host 'Enter a user name for the standard account'
do {
    $pw1 = Read-Host 'Enter password'
    $pw2 = Read-Host 'Confirm password'
    if ($pw1 -ne $pw2) {
        Write-Warning 'Passwords do not match. Please try again.'
    }
} until ($pw1 -eq $pw2)

net user $username $pw1 /add
net localgroup Users $username /add

Write-Host "Created standard user account '$username'."
