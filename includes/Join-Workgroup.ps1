# Automatically join the predefined workgroup if not already joined
$CurrentWorkgroup = (Get-WmiObject Win32_ComputerSystem).Workgroup
$WORKGROUP = 'MYLOCALCHEMIST'

Write-Host ($CR + "Current workgroup: $CurrentWorkgroup") -foregroundcolor $FOREGROUNDCOLOR

if ($CurrentWorkgroup -eq $WORKGROUP) {
    Write-Host ($CR + "Already joined to workgroup '$WORKGROUP'. Skipping.") -foregroundcolor $FOREGROUNDCOLOR $CR
    return
}

Write-Host ($CR + "Joining workgroup '$WORKGROUP'") -foregroundcolor $FOREGROUNDCOLOR $CR
Try {
    Add-Computer -WorkgroupName $WORKGROUP -ErrorAction Stop
} Catch {
    Write-Warning $Error[0]
}
Write-Host ("Joined to workgroup $WORKGROUP") -foregroundcolor $FOREGROUNDCOLOR $CR
