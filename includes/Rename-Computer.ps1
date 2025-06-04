# Display the current computer name and ask whether it should be changed
$CurrentName = $env:COMPUTERNAME
Write-Host ($CR + "Current computer name: $CurrentName") -foregroundcolor $FOREGROUNDCOLOR
$confirmation = Read-Host "Do you want to change the computer name? [y/N]"
if ($confirmation -eq 'y') {
    $HOSTNAME = Read-Host "Enter new computer name"

    Write-Host ($CR + "Hostname will be changed") -foregroundcolor $FOREGROUNDCOLOR $CR
    Try {
        Rename-Computer -NewName $HOSTNAME -ErrorAction Stop
    } Catch {
        Write-Warning $Error[0]
    }
    Write-Host ("Server renamed to $HOSTNAME") -foregroundcolor $FOREGROUNDCOLOR $CR
} else {
    Write-Host "Hostname change skipped." -foregroundcolor $FOREGROUNDCOLOR $CR
}
