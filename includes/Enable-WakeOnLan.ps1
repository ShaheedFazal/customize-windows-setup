# Enable Wake on LAN (WoL) on the local machine

Write-Host "[INFO] Configuring Wake on LAN..."

# Filter for physical, active Ethernet adapters only
Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -match "Ethernet" -and
    $_.Status -eq "Up" -and
    $_.HardwareInterface -eq $true
} | ForEach-Object {
    $adapterName = $_.Name
    Write-Host "Processing adapter: $adapterName"

    # Enable "Wake on Magic Packet"
    try {
        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName "Wake on Magic Packet" -DisplayValue "Enabled" -NoRestart -ErrorAction Stop
        Write-Host "[OK] Enabled Wake on Magic Packet on $adapterName"
    } catch {
        Write-Host "[WARN] Could not set Wake on Magic Packet on $adapterName. $_"
    }

    # Set power management options
    try {
        powercfg -devicequery wake_from_any | Where-Object { $_ -like "*$adapterName*" } | ForEach-Object {
            powercfg -devicedisablewake $_
            powercfg -deviceenablewake $_
        }
        Write-Host "[OK] Enabled wake permissions in power management for $adapterName"
    } catch {
        Write-Host "[WARN] Could not configure power settings for $adapterName. $_"
    }
}

Write-Host "[DONE] Wake on LAN configuration complete."
