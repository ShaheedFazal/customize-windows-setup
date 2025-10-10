# Enable Wake on LAN (WoL) on the local machine

Write-Host "[INFO] Configuring Wake on LAN..."

# Get all network adapters and show what we found
$allAdapters = Get-NetAdapter
Write-Host "[INFO] Found $($allAdapters.Count) total network adapters"

# Filter for physical network adapters using a more universal approach
$eligibleAdapters = Get-NetAdapter | Where-Object {
    # Must be a hardware interface (not virtual)
    $_.HardwareInterface -eq $true -and
    # Exclude known virtual/software adapters by description patterns
    $_.InterfaceDescription -notmatch "Virtual|VPN|TAP|Loopback|Teredo|6to4|Fortinet|Hyper-V|VMware|Bluetooth|Tunnel" -and
    # Only include adapters that can potentially support Wake on LAN (have advanced properties)
    (Get-NetAdapterAdvancedProperty -Name $_.Name -ErrorAction SilentlyContinue | 
     Where-Object { $_.DisplayName -match "Wake|Power" }) -ne $null
}

Write-Host "[INFO] Found $($eligibleAdapters.Count) eligible physical network adapters"

if ($eligibleAdapters.Count -eq 0) {
    Write-Host "[WARN] No eligible network adapters found for Wake on LAN configuration"
    Write-Host "[INFO] Adapter types found:"
    $allAdapters | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.InterfaceDescription) (Status: $($_.Status), Hardware: $($_.HardwareInterface))"
    }
} else {
    $eligibleAdapters | ForEach-Object {
        $adapterName = $_.Name
        $adapterDesc = $_.InterfaceDescription
        $adapterStatus = $_.Status
        
        Write-Host "[PROCESSING] $adapterName ($adapterDesc) - Status: $adapterStatus" -ForegroundColor Cyan

        # Try to enable Wake on Magic Packet using multiple possible property names
        $wakeEnabled = $false
        $possibleWakeProperties = @(
            "Wake on Magic Packet",
            "*Wake*Magic*",
            "Wake on Pattern Match",
            "*Wake*",
            "WakeOnMagicPacket"
        )

        foreach ($wakeProp in $possibleWakeProperties) {
            try {
                # Try to find and set the wake property
                $properties = Get-NetAdapterAdvancedProperty -Name $adapterName -ErrorAction SilentlyContinue | 
                              Where-Object { $_.DisplayName -like $wakeProp }
                
                if ($properties) {
                    foreach ($prop in $properties) {
                        # Get current value for comparison and available options
                        $currentValue = $prop.DisplayValue
                        Write-Host "[INFO] Current value for '$($prop.DisplayName)': $currentValue" -ForegroundColor Gray
                        
                        # Common enabled values - prioritize numeric values first for universal compatibility
                        $enabledValues = @("1", "0x1", "Enabled", "On", "True", "Aktiviert", "Ein", "Oui")
                        
                        # Try each enabled value until one works
                        $propertyEnabled = $false
                        foreach ($enableValue in $enabledValues) {
                            try {
                                Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $prop.DisplayName -DisplayValue $enableValue -NoRestart -ErrorAction Stop
                                Write-Host "[OK] Enabled '$($prop.DisplayName)' on $adapterName (using '$enableValue')" -ForegroundColor Green
                                $wakeEnabled = $true
                                $propertyEnabled = $true
                                break
                            } catch {
                                # Continue trying other values
                                continue
                            }
                        }
                        
                        if (-not $propertyEnabled) {
                            # Get valid values if available
                            try {
                                $validValues = Get-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $prop.DisplayName -ErrorAction SilentlyContinue | 
                                              Select-Object -ExpandProperty ValidDisplayValues -ErrorAction SilentlyContinue
                                if ($validValues) {
                                    Write-Host "[INFO] Valid values for '$($prop.DisplayName)': $($validValues -join ', ')" -ForegroundColor Gray
                                    # Try to find an enabled-like value from valid options
                                    $enabledOption = $validValues | Where-Object { $_ -in $enabledValues } | Select-Object -First 1
                                    if ($enabledOption) {
                                        try {
                                            Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName $prop.DisplayName -DisplayValue $enabledOption -NoRestart -ErrorAction Stop
                                            Write-Host "[OK] Enabled '$($prop.DisplayName)' on $adapterName (using valid option '$enabledOption')" -ForegroundColor Green
                                            $wakeEnabled = $true
                                            $propertyEnabled = $true
                                        } catch {
                                            Write-Host "[WARN] Failed to set '$($prop.DisplayName)' to '$enabledOption'" -ForegroundColor Yellow
                                        }
                                    }
                                }
                            } catch {
                                Write-Host "[WARN] Could not determine valid values for '$($prop.DisplayName)'" -ForegroundColor Yellow
                            }
                        }
                        
                        if (-not $propertyEnabled) {
                            Write-Host "[WARN] Could not enable '$($prop.DisplayName)' on $adapterName" -ForegroundColor Yellow
                        }
                    }
                }
            } catch {
                continue
            }
        }

        # Configure Windows power management to allow this device to wake the computer
        try {
            # Enable wake capability via registry (more reliable than powercfg for some adapters)
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
            $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            
            foreach ($subKey in $subKeys) {
                try {
                    $adapterKey = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
                    if ($adapterKey -and ($adapterKey.DriverDesc -eq $adapterDesc -or $adapterKey.DriverDesc -like "*$($adapterName)*")) {
                        # Enable Wake on Magic Packet in registry using numeric values (universal)
                        Set-ItemProperty -Path $subKey.PSPath -Name "*WakeOnMagicPacket" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $subKey.PSPath -Name "WakeOnLink" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $subKey.PSPath -Name "PMWiFiRekeyOffload" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        
                        # Try additional common wake properties with numeric values
                        Set-ItemProperty -Path $subKey.PSPath -Name "*WakeOnPattern" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $subKey.PSPath -Name "EnableWakeOnLan" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $subKey.PSPath -Name "WolShutdownLinkSpeed" -Value 2 -Type DWord -ErrorAction SilentlyContinue # 2 = No speed reduction
                        
                        Write-Host "[OK] Configured registry wake settings for $adapterName (using numeric values)" -ForegroundColor Green
                        break
                    }
                } catch {
                    continue
                }
            }
        } catch {
            Write-Host "[WARN] Could not configure registry wake settings for $adapterName" -ForegroundColor Yellow
        }

        if ($wakeEnabled) {
            Write-Host "[SUCCESS] Wake on LAN configured for $adapterName" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Wake on LAN may not be fully supported on $adapterName" -ForegroundColor Yellow
        }
    }
}

Write-Host "[INFO] Wake on LAN configuration complete." -ForegroundColor Cyan
