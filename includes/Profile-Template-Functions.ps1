# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS (v2 - Corrected)
# ============================================================================

# ============================================================================
# SECTION 1: HIVE MOUNTING FUNCTIONS
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
        reg unload "$mountPoint" | Out-Null
        Write-Host "[TEMPLATE] Dismounted default user hive" -ForegroundColor Green
    }
    catch {
        Write-Host "[TEMPLATE] Failed to dismount default user hive - $_" -ForegroundColor Yellow
    }
}


# ============================================================================
# SECTION 2: DATA DEFINITION
# ============================================================================

function Get-ProfileTemplateSections {
    [CmdletBinding()]
    param()

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
# ============================================================================

function Copy-SpecificRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Section
    )

    try {
        foreach ($valueName in $Section.CopySpecificValues) {
            try {
                if (!(Test-Path $Section.Source)) {
                    Write-Host "    Skipped: Source path $($Section.Source) not found for value '$valueName'." -ForegroundColor Yellow
                    continue
                }

                $valueData = (Get-ItemProperty -Path $Section.Source -Name $valueName -ErrorAction Stop).$valueName
                $valueType = (Get-Item -Path $Section.Source).GetValueKind($valueName)
                
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
        [Parameter(Mandatory = $true)] [string]$SourcePath,
        [Parameter(Mandatory = $true)] [string]$DestinationPath,
        [Parameter(Mandatory = $false)] [switch]$FilterPersonalData
    )

    try {
        if (!(Test-Path $SourcePath)) {
            Write-Host "  ✓ Skipped: Source path '$SourcePath' not found." -ForegroundColor Gray
            return $true
        }

        $sourceProperties = Get-ItemProperty -Path $SourcePath
        if ($null -eq $sourceProperties) { return $true }

        if (!(Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -Force | Out-Null
        }
        
        $propNames = $sourceProperties.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | Select-Object -ExpandProperty Name
        $personalProperties = @("Email", "UserName", "DesktopWallpaper", "EncodedPassword")

        foreach ($propName in $propNames) {
            if ($FilterPersonalData.IsPresent -and $personalProperties -contains $propName) {
                Write-Host "    Skipped personal property: $propName" -ForegroundColor Yellow
                continue
            }
            
            try {
                $valueData = $sourceProperties.$propName
                $valueType = (Get-Item -Path $SourcePath).GetValueKind($propName)
                Set-ItemProperty -Path $DestinationPath -Name $propName -Value $valueData -Type $valueType -Force -ErrorAction Stop | Out-Null
            } catch {
                 Write-Host "    Failed to copy property '$propName' in key '$SourcePath' - $_" -ForegroundColor Yellow
            }
        }

        Write-Host "  ✓ Completed copying section for: $($DestinationPath)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ✗ Failed to copy key: $SourcePath - $_" -ForegroundColor Red
        return $false
    }
}


# ============================================================================
# SECTION 4: ORCHESTRATION AND EXECUTION
# ============================================================================

function Copy-SafeRegistrySections {
    [CmdletBinding()]
    param()

    $sections = Get-ProfileTemplateSections
    $successCount = 0
    $totalCount = $sections.Count

    Write-Host "[TEMPLATE] Processing $($totalCount) registry sections..." -ForegroundColor Cyan

    foreach ($section in $sections) {
        Write-Host "  Processing: $($section.Description)"
        
        $sectionSuccess = $false
        if ($section.PSObject.Properties.Name -contains 'CopySpecificValues') {
            $sectionSuccess = Copy-SpecificRegistryValues -Section $section
        }
        else {
            $sectionSuccess = Copy-RegistryKeyContents -SourcePath $section.Source -DestinationPath $section.Destination -FilterPersonalData:$section.FilterPersonalData
        }

        if ($sectionSuccess) { $successCount++ }
    }

    return ($successCount -eq $totalCount)
}

function Invoke-ProfileTemplate {
    [CmdletBinding()]
    param()

    if (-not (Mount-DefaultUserHive)) {
        Write-Host "[TEMPLATE] Failed to mount default user hive - aborting." -ForegroundColor Red
        return $false
    }

    try {
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

Export-ModuleMember -Function *
