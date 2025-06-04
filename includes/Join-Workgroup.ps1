# Display the current workgroup and ask whether it should be changed
$CurrentWorkgroup = (Get-WmiObject Win32_ComputerSystem).Workgroup
Write-Host ($CR + "Current workgroup: $CurrentWorkgroup") -foregroundcolor $FOREGROUNDCOLOR
$confirmation = Read-Host "Do you want to change the workgroup? [y/N]"
if ($confirmation -eq 'y') {
    $WORKGROUP = Read-Host "Enter new workgroup"

    Write-Host ($CR + "Join to workgroup") -foregroundcolor $FOREGROUNDCOLOR $CR
    Try {
        Add-Computer -WorkgroupName $WORKGROUP -ErrorAction Stop
    } Catch {
        Write-Warning $Error[0]
    }
    Write-Host ("Joined to workgroup $WORKGROUP") -foregroundcolor $FOREGROUNDCOLOR $CR
} else {
    Write-Host "Workgroup change skipped." -foregroundcolor $FOREGROUNDCOLOR $CR
}
