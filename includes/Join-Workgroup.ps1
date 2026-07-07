if (Test-MachineWideSentinel -Name 'Join-Workgroup') { return }

# Automatically join the predefined workgroup if not already joined
$CurrentWorkgroup = (Get-WmiObject Win32_ComputerSystem).Workgroup
$WORKGROUP = 'MYLOCALCHEMIST'

# File and Printer Sharing / Network Discovery below is for pharmacy workstation
# LANs - peer-to-peer sharing within a branch. Servers must NOT expose it:
# GFC-SERVER-01 is administered remotely over the cloudflared tunnel, has its
# network-logon right relaxed for SSH (see Ensure-Apps.ps1), and serves no
# shares - so inbound SMB/NetBIOS there is pure lateral-movement surface. For
# those hosts we DISABLE sharing on every run instead of enabling it. Keep this
# list in sync with $sshHosts in Ensure-Apps.ps1.
$noFileSharingHosts = @('GFC-SERVER-01')

if ($env:COMPUTERNAME -in $noFileSharingHosts) {
    Write-Host ($CR + "Server host '$env:COMPUTERNAME' - disabling File and Printer Sharing / Network Discovery") -foregroundcolor $FOREGROUNDCOLOR
    if ($CurrentWorkgroup -ne $WORKGROUP) {
        Try { Add-Computer -WorkgroupName $WORKGROUP -ErrorAction Stop } Catch { Write-Warning $Error[0] }
    }
    foreach ($grp in 'File and Printer Sharing', 'Network Discovery') {
        Disable-NetFirewallRule -DisplayGroup $grp -ErrorAction SilentlyContinue
    }
    Write-Log "Server host $env:COMPUTERNAME: File and Printer Sharing + Network Discovery disabled (not a P2P sharing node)"
    return
}

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

# Configure network sharing settings
Write-Host ($CR + "Configuring network sharing for workgroup...") -foregroundcolor $FOREGROUNDCOLOR

try {
    # Set all network connections to Private profile
    Write-Log "Setting network profiles to Private"

    Get-NetConnectionProfile | ForEach-Object {
        $currentProfile = $_.Name
        try {
            Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
            Write-Log "Set network '$currentProfile' to Private"
        } catch {
            Write-Log "WARNING: Could not set '$currentProfile' to Private - $_"
        }
    }

    Write-Host ("Network profiles set to Private") -foregroundcolor $FOREGROUNDCOLOR

} catch {
    Write-Log "ERROR: Failed to configure network profiles - $_"
    Write-Host "[ERROR] Failed to configure network profiles: $_" -ForegroundColor Red
}

try {
    # Enable Network Discovery via registry (system-wide enforcement)
    Write-Log "Enabling Network Discovery"

    # Enable Network Discovery for Private networks
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" `
                      -Name "NC_ShowSharedAccessUI" `
                      -Value 1 `
                      -Type "DWord" `
                      -Force

    # Enable File and Printer Sharing
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
                      -Name "AutoShareWks" `
                      -Value 1 `
                      -Type "DWord" `
                      -Force

    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
                      -Name "AutoShareServer" `
                      -Value 1 `
                      -Type "DWord" `
                      -Force

    Write-Log "Registry settings for Network Discovery configured"

} catch {
    Write-Log "ERROR: Failed to configure Network Discovery registry settings - $_"
    Write-Host "[ERROR] Failed to configure Network Discovery: $_" -ForegroundColor Red
}

try {
    # Enable Network Discovery and File Sharing via firewall rules
    Write-Log "Enabling Network Discovery and File Sharing firewall rules"

    # Enable Network Discovery firewall rules
    Enable-NetFirewallRule -DisplayGroup "Network Discovery" -ErrorAction SilentlyContinue
    Write-Log "Network Discovery firewall rules enabled"

    # Enable File and Printer Sharing firewall rules
    Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue
    Write-Log "File and Printer Sharing firewall rules enabled"

    Write-Host ("Network Discovery and File Sharing enabled") -foregroundcolor $FOREGROUNDCOLOR

} catch {
    Write-Log "ERROR: Failed to enable firewall rules - $_"
    Write-Host "[ERROR] Failed to enable firewall rules: $_" -ForegroundColor Red
}

try {
    # Start and enable required services
    Write-Log "Configuring network sharing services"

    $services = @(
        "FDResPub",      # Function Discovery Resource Publication
        "SSDPSRV",       # SSDP Discovery
        "upnphost",      # UPnP Device Host
        "LanmanServer",  # Server (for file sharing)
        "LanmanWorkstation" # Workstation (for accessing shares)
    )

    foreach ($serviceName in $services) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                Set-Service -Name $serviceName -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                Write-Log "Service '$serviceName' configured and started"
            }
        } catch {
            Write-Log "WARNING: Could not configure service '$serviceName' - $_"
        }
    }

    Write-Host ("Network sharing services configured") -foregroundcolor $FOREGROUNDCOLOR

} catch {
    Write-Log "ERROR: Failed to configure network sharing services - $_"
    Write-Host "[ERROR] Failed to configure services: $_" -ForegroundColor Red
}

Write-Host ($CR + "Network sharing configuration completed") -foregroundcolor $FOREGROUNDCOLOR
Write-Host ($CR + "Note: A reboot may be required for all changes to take effect") -foregroundcolor Yellow $CR
