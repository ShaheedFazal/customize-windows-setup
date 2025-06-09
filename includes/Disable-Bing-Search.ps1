# Disable Bing Search
try {
    $searchPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (!(Test-Path $searchPath)) {
        New-Item -Path $searchPath -Force | Out-Null
    }
    Set-ItemProperty -Path $searchPath -Name "DisableWebSearch" -Type DWord -Value 1
    Set-ItemProperty -Path $searchPath -Name "AllowCortana" -Type DWord -Value 0
    Set-ItemProperty -Path $searchPath -Name "ConnectedSearchUseWeb" -Type DWord -Value 0
    Write-Host "[OK] Policy applied: Bing web search disabled system-wide"
} catch {
    Write-Host "[WARN] Could not apply Bing search policy: $($_.Exception.Message)"
}
