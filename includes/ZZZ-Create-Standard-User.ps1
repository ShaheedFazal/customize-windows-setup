## Create standard user account

$confirm = Read-Host 'Create a new standard user account? [y/N]'
if ($confirm -ne 'y') {
    Write-Host 'User creation cancelled.'
    return
}

$username = New-LocalUserAccount -AccountType 'Standard'
if ($null -ne $username) {
    Write-Host "Created standard user account '$username'."
} else {
    Write-Warning 'Failed to create the standard user account. Check log for details.'
}
