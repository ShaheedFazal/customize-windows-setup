# Disable WiFi Sense: HotSpot Sharing
$hotSpotReportingPath = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"
if (!(Test-Path $hotSpotReportingPath)) {
    New-Item -Path $hotSpotReportingPath -Force | Out-Null
}
New-ItemProperty -Path $hotSpotReportingPath -Name "value" -PropertyType DWord -Value 0 -Force

# Disable WiFi Sense: Shared HotSpot Auto-Connect
$autoConnectPath = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots"
if (!(Test-Path $autoConnectPath)) {
    New-Item -Path $autoConnectPath -Force | Out-Null
}
New-ItemProperty -Path $autoConnectPath -Name "value" -PropertyType DWord -Value 0 -Force
