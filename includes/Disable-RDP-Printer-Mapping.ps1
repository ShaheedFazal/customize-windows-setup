# Disable RDP printer mapping
# Registry path for Remote Desktop printer redirection settings
$regkeyRDPPrinterMapping = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"

# Disable printer redirection over RDP
Set-ItemProperty -Path $regkeyRDPPrinterMapping -Name 'fDisableCpm' -Value 1
