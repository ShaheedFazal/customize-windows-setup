# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS
# ============================================================================

function Mount-DefaultUserHive {
    [CmdletBinding()]
    param()
    try {
        $defaultProfilePath = "C:\\Users\\Default\\NTUSER.DAT"
        $mountPoint = "HKU\\DEFAULT_TEMPLATE"

        if (!(Test-Path $defaultProfilePath)) {
            throw "Default user profile not found: $defaultProfilePath"
        }

        $result = & reg.exe load "HKU\\DEFAULT_TEMPLATE" "C:\\Users\\Default\\NTUSER.DAT" 2>&1
        if ($LASTEXITCODE -ne 0) {
            if (Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -eq 'DEFAULT_TEMPLATE' }) {
                Write-Host "[TEMPLATE] Default user hive already mounted" -ForegroundColor Yellow
                return $true
            }
            throw "Failed to mount default user hive: $result"
        }

        Write-Host "[TEMPLATE] Mounted default user hive at $mountPoint" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to mount default user hive: $_" -ForegroundColor Red
        return $false
    }
}

function Dismount-DefaultUserHive {
    [CmdletBinding()]
    param()
    try {
        $mountPoint = "HKU\\DEFAULT_TEMPLATE"
        if (Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -like '*DEFAULT_TEMPLATE' }) {
            $result = & reg.exe unload "HKU\\DEFAULT_TEMPLATE" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to dismount default user hive: $result"
            }
            Write-Host "[TEMPLATE] Dismounted default user hive" -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to dismount default user hive: $_" -ForegroundColor Red
        return $false
    }
}

function Copy-RegistrySection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    try {
        if (!(Test-Path $SourcePath)) {
            Write-Host "[TEMPLATE] Source path not found: $SourcePath" -ForegroundColor Yellow
            return $false
        }
        $result = reg copy $SourcePath $DestinationPath /s /f 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[TEMPLATE] Copied $SourcePath" -ForegroundColor Green
            return $true
        } else {
            throw $result
        }
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to copy $SourcePath : $_" -ForegroundColor Red
        return $false
    }
}

function Remove-PersonalPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$KeyPath)
    try {
        if (Test-Path $KeyPath) {
            $userPath = [regex]::Escape($env:USERPROFILE)
            $props = Get-ItemProperty -Path $KeyPath
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Value -is [string] -and $prop.Value -match $userPath) {
                    Remove-ItemProperty -Path $KeyPath -Name $prop.Name -ErrorAction SilentlyContinue
                    Write-Host "[TEMPLATE] Removed personal path from $KeyPath\\$($prop.Name)" -ForegroundColor Yellow
                }
            }
        }
        return $true
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to clean $KeyPath : $_" -ForegroundColor Red
        return $false
    }
}

function Filter-RegistrySection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$KeyPath)
    Remove-PersonalPaths -KeyPath $KeyPath | Out-Null
}

function Test-TemplatingRequirements {
    [CmdletBinding()]
    param()

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        Write-Host "[TEMPLATE] Administrator privileges required" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path "C:\\Users\\Default\\NTUSER.DAT")) {
        Write-Host "[TEMPLATE] Default user profile not found" -ForegroundColor Red
        return $false
    }

    Write-Host "[TEMPLATE] Technical requirements satisfied" -ForegroundColor Green
    return $true
}

function Backup-DefaultProfile {
    [CmdletBinding()]
    param()
    try {
        $source = 'C:\\Users\\Default'
        $backup = 'C:\\Users\\Default.backup'

        if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null

        $exclude = @('Application Data', 'History')
        robocopy $source $backup /MIR /XJ /XD $exclude | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Robocopy failed with exit code $LASTEXITCODE"
        }

        Write-Host "[TEMPLATE] Backup created at $backup" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to backup default profile: $_" -ForegroundColor Red
        return $false
    }
}

function Restore-DefaultProfile {
    [CmdletBinding()]
    param()
    try {
        $backup = 'C:\\Users\\Default.backup'
        $dest   = 'C:\\Users\\Default'
        if (Test-Path $backup) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null

            $exclude = @('Application Data', 'History')
            robocopy $backup $dest /MIR /XJ /XD $exclude | Out-Null
            if ($LASTEXITCODE -ge 8) {
                throw "Robocopy failed with exit code $LASTEXITCODE"
            }

            Write-Host "[TEMPLATE] Restored default profile from backup" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to restore default profile: $_" -ForegroundColor Red
    }
}

function Remove-PersonalDataFromSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    $personalDataValues = @(
        'Wallpaper',
        'RecentDocs',
        'RunMRU',
        'LastVisited*',
        'MostRecentApplication',
        'TypedPaths',
        'TypedURLs'
    )

    Write-Host "    Filtering personal data..." -ForegroundColor Gray

    foreach ($valueName in $personalDataValues) {
        try {
            if ($valueName.Contains('*')) {
                $pattern = $valueName.Replace('*', '')
                $allValues = Get-Item -Path $RegistryPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
                $matchingValues = $allValues | Where-Object { $_ -like "*$pattern*" }

                foreach ($matchingValue in $matchingValues) {
                    Remove-ItemProperty -Path $RegistryPath -Name $matchingValue -Force -ErrorAction SilentlyContinue
                    Write-Host "      Removed: $matchingValue" -ForegroundColor Gray
                }
            } else {
                if (Get-ItemProperty -Path $RegistryPath -Name $valueName -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty -Path $RegistryPath -Name $valueName -Force -ErrorAction SilentlyContinue
                    Write-Host "      Removed: $valueName" -ForegroundColor Gray
                }
            }
        }
        catch {
        }
    }
}

function Copy-SpecificRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Section
    )

    try {
        if (!(Test-Path $Section.Destination)) {
            New-Item -Path $Section.Destination -Force | Out-Null
        }

        foreach ($valueName in $Section.CopySpecificValues) {
            try {
                $value = Get-ItemProperty -Path $Section.Source -Name $valueName -ErrorAction SilentlyContinue
                if ($value) {
                    $valueData = $value.$valueName
                    $valueType = (Get-Item -Path $Section.Source).GetValueKind($valueName)

                    Set-ItemProperty -Path $Section.Destination -Name $valueName -Value $valueData -Type $valueType -Force
                    Write-Host "    Copied value: $valueName" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "    Failed to copy value: $valueName - $_" -ForegroundColor Yellow
            }
        }

        Write-Host "  \u2713 Completed: $($Section.Description)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  \u2717 Failed: $($Section.Description) - $_" -ForegroundColor Red
        return $false
    }
}

function Copy-RegistryToDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [switch]$FilterPersonalData
    )

    try {
        if (!(Test-Path $SourcePath)) {
            Write-Host "    Source path not found: $SourcePath" -ForegroundColor Yellow
            return $false
        }

        $result = reg copy "$SourcePath" "$DestinationPath" /s /f 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Copied registry section" -ForegroundColor Gray

            if ($FilterPersonalData) {
                Remove-PersonalDataFromSection -RegistryPath $DestinationPath
            }

            return $true
        } else {
            Write-Host "    Failed to copy registry section: $result" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "    Exception during copy: $_" -ForegroundColor Red
        return $false
    }
}

function Get-SafeTemplateSections {
    <#
    .SYNOPSIS
    Returns array of registry sections that are safe to copy from current user to default profile

    .DESCRIPTION
    These sections contain UI preferences and settings that enhance user experience
    without containing personal data or risky configurations.
    #>

    return @(
        @{ Source = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced"; Description = "Explorer Advanced Settings (taskbar, file extensions, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\\Control Panel\\Desktop"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Control Panel\\Desktop"; Description = "Desktop and screensaver settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\\Control Panel\\Keyboard"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Control Panel\\Keyboard"; Description = "Keyboard settings (NumLock, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Software\\Microsoft\\Windows\\CurrentVersion\\Search"; Description = "Windows Search preferences"; FilterPersonalData = $true },
        @{ Source = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager"; Description = "Content delivery and privacy settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer"; Destination = "HKU:\\DEFAULT_TEMPLATE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer"; Description = "Explorer recent items settings"; FilterPersonalData = $true; CopySpecificValues = @('ShowRecent','ShowFrequent') }
    )
}

function Copy-SafeRegistrySections {
    [CmdletBinding()]
    param()

    $sections = Get-SafeTemplateSections
    $successCount = 0
    $totalCount = $sections.Count

    Write-Host "[TEMPLATE] Processing $totalCount registry sections..." -ForegroundColor Cyan

    foreach ($section in $sections) {
        Write-Host "  Processing: $($section.Description)" -ForegroundColor Gray

        if ($section.CopySpecificValues) {
            $sectionSuccess = Copy-SpecificRegistryValues -Section $section
        } else {
            $sectionSuccess = Copy-RegistryToDefault -SourcePath $section.Source -DestinationPath $section.Destination -FilterPersonalData:$section.FilterPersonalData
        }

        if ($sectionSuccess) {
            $successCount++
        }
    }

    Write-Host "[TEMPLATE] Successfully templated $successCount of $totalCount sections" -ForegroundColor Cyan
    return ($successCount -eq $totalCount)
}

function Invoke-ProfileTemplating {
    [CmdletBinding()]
    param(
        [switch]$Backup = $true
    )

    Write-Host "`n[TEMPLATE] Starting profile templating process..." -ForegroundColor Cyan

    if (-not (Test-TemplatingRequirements)) {
        Write-Host "[TEMPLATE] Templating cancelled - technical requirements not met" -ForegroundColor Red
        return $false
    }

    if ($Backup) {
        if (-not (Backup-DefaultProfile)) {
            Write-Host "[TEMPLATE] Failed to backup default profile - aborting" -ForegroundColor Red
            return $false
        }
    }

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



