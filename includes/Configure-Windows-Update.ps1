# Enable automatic updates (Auto download and schedule install)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 4 -Type "DWord" -Force

# Prevent auto-reboot while users are logged on
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type "DWord" -Force

# Suppress reboot warning prompts
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "RebootWarningTimeoutEnabled" -Value 0 -Type "DWord" -Force

# Set Active Hours (8 AM to 7 PM)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursStart" -Value 8 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursEnd" -Value 19 -Type "DWord" -Force

# Defer Feature Updates for 180 days
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -Value 1 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 180 -Type "DWord" -Force

# Defer Quality Updates for 7 days
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdates" -Value 1 -Type "DWord" -Force
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdatesPeriodInDays" -Value 7 -Type "DWord" -Force

# Enable driver updates via Windows Update
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 1 -Type "DWord" -Force

# Enable recommended updates
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "IncludeRecommendedUpdates" -Value 1 -Type "DWord" -Force

# Disable Delivery Optimisation to prevent internet sharing of updates
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Type "DWord" -Force

# Optional: Limit background download bandwidth to 50%
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DOMaxDownloadBandwidth" -Value 50 -Type "DWord" -Force

# Clean up old Windows update files
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
