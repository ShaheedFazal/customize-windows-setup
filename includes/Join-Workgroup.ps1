# Automatically join the predefined workgroup
$CurrentWorkgroup = (Get-WmiObject Win32_ComputerSystem).Workgroup
Write-Host ($CR + "Current workgroup: $CurrentWorkgroup") -foregroundcolor $FOREGROUNDCOLOR

$WORKGROUP = 'MYLOCALCHEMIST'
Write-Host ($CR + "Joining workgroup '$WORKGROUP'") -foregroundcolor $FOREGROUNDCOLOR $CR
Try {
    Add-Computer -WorkgroupName $WORKGROUP -ErrorAction Stop
} Catch {
    Write-Warning $Error[0]
}
Write-Host ("Joined to workgroup $WORKGROUP") -foregroundcolor $FOREGROUNDCOLOR $CR
