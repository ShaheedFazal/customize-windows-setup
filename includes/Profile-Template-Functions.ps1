# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS
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

function Copy-SpecificRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Section
    )

    try {
        $values = Get-Item -Path $Section.Source | Get-ItemProperty | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

        foreach ($valueName in $values) {
            $valueData = (Get-ItemProperty -Path $Section.Source -Name $valueName).$valueName

            try {
                $valueType = (Get-Item -Path $Section.Source).GetValueKind($valueName)

                if (Get-ItemProperty -Path $Section.Destination -Name $valueName -ErrorAction SilentlyContinue) {
                    Set-ItemProperty -Path $Section.Destination -Name $valueName -Value $valueData -Force
                } else {
                    New-ItemProperty -Path $Section.Destination -Name $valueName -Value $valueData -PropertyType $valueType -Force | Out-Null
                }

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

function Copy-RegistryToDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        [switch]$FilterPersonalData
    )

    try {
        if (!(Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -Force | Out-Null
        }

        $properties = Get-ItemProperty -Path $SourcePath
        $props = $properties | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

        foreach ($prop in $props) {
            if ($FilterPersonalData -and $prop -match '(Email|UserName|DesktopWallpaper)') {
                Write-Host "    Skipped personal data property: $prop" -ForegroundColor Yellow
                continue
            }

            $value = $properties.$prop
            Set-ItemProperty -Path $DestinationPath -Name $prop -Value $value -Force
            Write-Host "    Copied property: $prop" -ForegroundColor Gray
        }

        return @(
            @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Description = "Explorer Advanced Settings (taskbar, file extensions, etc.)"; FilterPersonalData = $false },
            @{ Source = "HKCU:\Control Panel\Desktop"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Desktop"; Description = "Desktop and screensaver settings"; FilterPersonalData = $true },
            @{ Source = "HKCU:\Control Panel\Keyboard"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Keyboard"; Description = "Keyboard settings (NumLock, etc.)"; FilterPersonalData = $false },
            @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Description = "Content delivery and privacy settings"; FilterPersonalData = $true },
            @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer"; Description = "Explorer recent items settings"; FilterPersonalData = $true; CopySpecificValues = @('ShowRecent','ShowFrequent') }
        )
    }
    catch {
        Write-Host "[ERROR] Failed to copy registry to default: $_" -ForegroundColor Red
        return $null
    }
}

function Get-SafeTemplateSections {
    [CmdletBinding()]
    param()

    return Copy-RegistryToDefault
}

function Copy-SafeRegistrySections {
    [CmdletBinding()]
    param()

    $sections = Get-SafeTemplateSections
    $successCount = 0
    $totalCount   = $sections.Count

    Write-Host "[TEMPLATE] Processing $($totalCount) registry sections..." -ForegroundColor Cyan

    foreach ($section in $sections) {
        Write-Host "  Processing: $($section.Description)" -ForegroundColor Gray

        if ($section.CopySpecificValues) {
            $sectionSuccess = Copy-SpecificRegistryValues -Section $section
        } else {
            $sectionSuccess = Copy-RegistryToDefault -SourcePath $section.Source -DestinationPath $section.Destination -FilterPersonalData:$section.FilterPersonalData
        }

        if ($sectionSuccess) { $successCount++ }
    }

    return ($successCount -eq $totalCount)
}

function Invoke-ProfileTemplate {
    [CmdletBinding()]
    param()

    if (-not (Mount-DefaultUserHive)) {
        Write-Host "[TEMPLATE] Failed to mount default user hive - aborting" -ForegroundColor Red
        return $false
    }

    try {
        $success = Copy-SafeRegistrySections

        if ($success) {
            Write-Host "[TEMPLATE] Profile templating completed successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[TEMPLATE] Profile templating completed with some errors" -ForegroundColor Yellow
            return $false
        }
    }
    finally {
        Dismount-DefaultUserHive
    }
}

Export-ModuleMember -Function *
