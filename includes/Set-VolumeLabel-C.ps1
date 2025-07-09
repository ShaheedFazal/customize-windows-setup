# Set volume label of C: to OS
try {
    $vol = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='C:'"
    Set-CimInstance -InputObject $vol -Property @{Label = $DRIVELABELSYS}
    Write-Host "[OK] Volume label set to $DRIVELABELSYS" -ForegroundColor Green
    return $true
} catch {
    Write-Host "[ERROR] Failed to set volume label: $_" -ForegroundColor Red
    return $false
}
