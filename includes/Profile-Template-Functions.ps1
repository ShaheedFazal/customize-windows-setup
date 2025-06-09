# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS (Corrected)
# ============================================================================

# ============================================================================
# SECTION 1: HIVE MOUNTING FUNCTIONS
# These functions handle mounting and dismounting the default user registry hive.
# No changes were needed here.
# ============================================================================

function Mount-DefaultUserHive {
    [CmdletBinding()]
    param()
    
    try {
        $defaultProfilePath = "C:\Users\Default\NTUSER.DAT"
        $mountPoint = "HKEY_USERS\DEFAULT_TEMPLATE"

        if (!(Test-Path $defaultProfilePath)) {
            throw "Default user profile hive not found at $defaultProfilePath"
        }

        # Suppress output from the reg command
        reg load "$mountPoint" $defaultProfilePath | Out-Null
        Write-Host "[TEMPLATE] Mounted default user hive" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[TEMPLATE] Failed to mount default user hive - $_" -ForegroundColor Red
        return $false
    }
}

function Dismount-DefaultUserHive {
    [CmdletBinding()]
    param()

    try {
        $mountPoint = "HKEY_USERS\DEFAULT_TEMPLATE"
        # Suppress output from the reg command
        reg unload "$mountPoint" | Out-Null
        Write-Host "[TEMPLATE] Dismounted default user hive" -ForegroundColor Green
    }
    catch {
        Write-Host "[TEMPLATE] Failed to dismount default user hive - $_" -ForegroundColor Yellow
    }
}


# ============================================================================
# SECTION 2: DATA DEFINITION
# This new function's only job is to define the registry sections to be copied.
# This separates the data from the logic, fixing the original parsing errors.
# ============================================================================

function Get-ProfileTemplateSections {
    [CmdletBinding()]
    param()

    # This array of hashtables defines all the registry keys and values to be copied.
    # This structure is now clean and isolated.
    return @(
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Description = "Explorer Advanced Settings (taskbar, file extensions, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\Control Panel\Desktop"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Desktop"; Description = "Desktop and screensaver settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\Control Panel\Keyboard"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Keyboard"; Description = "Keyboard settings (NumLock, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Description = "Content delivery and privacy settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer"; Description = "Explorer recent items settings"; CopySpecificValues = @('ShowRecent', 'ShowFrequent') }
    )
}


# ============================================================================
# SECTION 3: REGISTRY COPYING FUNCTIONS
# These functions now have clear, single purposes: to copy registry data.
# ============================================================================

function Copy-SpecificRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Section
    )

    try {
        # CORRECTED LOGIC: This now iterates through the list of values specified
        # in the 'CopySpecificValues' key of the section hashtable.
        foreach ($valueName in $Section.CopySpecificValues) {
            try {
                if (!(Test-Path $Section.Source)) {
                    Write-Host "    Skipped: Source path $($Section.Source) not found for value '$valueName'." -ForegroundColor Yellow
                    continue
                }

                $valueData = (Get-ItemProperty -Path $Section.Source -Name $valueName -ErrorAction Stop).$valueName
                $valueType = (Get-Item -Path $Section.Source).GetValueKind($valueName)
                
                # Ensure the destination path exists
                if (!(Test-Path $Section.Destination)) {
                    New-Item -Path $Section.Destination -Force | Out-Null
                }

                New-ItemProperty -Path $Section.Destination -Name $valueName -Value $valueData -PropertyType $valueType -Force | Out-Null
                Write-Host "    Copied value: $valueName" -ForegroundColor Gray
            }
            catch {
                Write-Host "    Failed to copy value: $valueName - $_" -ForegroundColor Yellow
            }
        }
        Write-Host "  ✓ Completed: $($Section.Description)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ✗ Failed: $($Section.Description) - $_" -ForegroundColor Red
        return $false
    }
}

function Copy-RegistryKeyContents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $false)]
        [switch]$FilterPersonalData
    )

    try {
        if (!(Test-Path $SourcePath)) {
             Write-Host "  ✓ Completed: $($Section.Description) (Source not found, skipped)" -ForegroundColor Gray
             return $true
        }
        if (!(Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -Force | Out-Null
        }

        # Copy the entire key with all its properties
        Copy-Item -Path $SourcePath -Destination $DestinationPath -Recurse -Force

        # If filtering is enabled, remove personal data from the new location
        if ($FilterPersonalData) {
            $personalProperties = @("Email", "UserName", "DesktopWallpaper", "EncodedPassword") # Add any others if needed
            foreach ($prop in $personalProperties) {
                if (Get-ItemProperty -Path $DestinationPath -Name $prop -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty -Path $DestinationPath -Name $prop -Force
                    Write-Host "    Removed personal property: $prop" -ForegroundColor Yellow
                }
            }
        }
        return $true
    }
    catch {
        Write-Host "  ✗ Failed to copy key: $SourcePath - $_" -ForegroundColor Red
        return $false
    }
}


# ============================================================================
# SECTION 4: ORCHESTRATION AND EXECUTION
# These functions coordinate the entire process using the corrected logic.
# ============================================================================

function Copy-SafeRegistrySections {
    [CmdletBinding()]
    param()

    # CORRECTED LOGIC: Get the clean data from our dedicated function.
    $sections = Get-ProfileTemplateSections
    $successCount = 0
    $totalCount = $sections.Count

    Write-Host "[TEMPLATE] Processing $($totalCount) registry sections..." -ForegroundColor Cyan

    foreach ($section in $sections) {
        Write-Host "  Processing: $($section.Description)"
        
        $sectionSuccess = $false
        # CORRECTED LOGIC: Check which function to call based on the section's definition.
        if ($section.PSObject.Properties.Name -contains 'CopySpecificValues') {
            # This section requires copying only specific named values.
            $sectionSuccess = Copy-SpecificRegistryValues -Section $section
        }
        else {
            # This section requires copying all values in the key.
            $sectionSuccess = Copy-RegistryKeyContents -SourcePath $section.Source -DestinationPath $section.Destination -FilterPersonalData:$section.FilterPersonalData
        }

        if ($sectionSuccess) { $successCount++ }
    }

    # Return true only if all sections succeeded
    return ($successCount -eq $totalCount)
}

function Invoke-ProfileTemplate {
    [CmdletBinding()]
    param()

    if (-not (Mount-DefaultUserHive)) {
        Write-Host "[TEMPLATE] Failed to mount default user hive - aborting." -ForegroundColor Red
        return $false
    }

    # The try/finally block ensures the hive is always dismounted, even if errors occur.
    try {
        # Call the orchestrator function
        $success = Copy-SafeRegistrySections

        if ($success) {
            Write-Host "[TEMPLATE] Profile templating completed successfully!" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "[TEMPLATE] Profile templating completed with some errors." -ForegroundColor Yellow
            return $false
        }
    }
    finally {
        Dismount-DefaultUserHive
    }
}

# Export all functions to make them available to the main script
Export-ModuleMember -Function *
