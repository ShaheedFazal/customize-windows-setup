# Disable WiFi Sense: HotSpot Sharing
$hotSpotReportingPath = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"
Set-RegistryValue -Path $hotSpotReportingPath -Name "value" -Value 0 -Type "DWord" -Force

# Disable WiFi Sense: Shared HotSpot Auto-Connect
$autoConnectPath = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots"
Set-RegistryValue -Path $autoConnectPath -Name "value" -Value 0 -Type "DWord" -Force

