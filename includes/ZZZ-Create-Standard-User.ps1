## Create standard user account

function ConvertTo-PlainText {
    param([System.Security.SecureString]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$username = Read-Host 'Enter a user name for the standard account'
do {
    $pw1 = Read-Host 'Enter password' -AsSecureString
    $pw2 = Read-Host 'Confirm password' -AsSecureString
    if ((ConvertTo-PlainText $pw1) -ne (ConvertTo-PlainText $pw2)) {
        Write-Warning 'Passwords do not match. Please try again.'
    }
} until ((ConvertTo-PlainText $pw1) -eq (ConvertTo-PlainText $pw2))

$plainPassword = ConvertTo-PlainText $pw1
net user $username $plainPassword /add
net localgroup Users $username /add

Write-Host "Created standard user account '$username'."
