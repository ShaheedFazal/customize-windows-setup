# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS
# ============================================================================

function Mount-DefaultUserHive {
    [CmdletBinding()]
    param()
    try {
        $defaultProfile = "C:\Users\Default\NTUSER.DAT"
        $mountPoint     = "HKEY_USERS\DEFAULT_TEMPLATE"

        if (-not (Test-Path $defaultProfile)) {
            throw "Default user hive not found at $defaultProfile"
        }

        reg load "$mountPoint" $defaultProfile | Out-Null
        Write-Host "[TEMPLATE] Mounted default user hive" -ForegroundColor Green
        return $true
    } catch {
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
    } catch {
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
        $names = Get-ItemProperty -Path $Section.Source \
                  | Get-Member -MemberType NoteProperty \
                  | Select-Object -ExpandProperty Name

        foreach ($name in $names) {
            $data = (Get-ItemProperty -Path $Section.Source -Name $name).$name
            $type = (Get-Item -Path $Section.Source).GetValueKind($name)
            try {
                if (Get-ItemProperty -Path $Section.Destination -Name $name -ErrorAction SilentlyContinue) {
                    Set-ItemProperty -Path $Section.Destination -Name $name -Value $data -Force
                } else {
                    New-ItemProperty -Path $Section.Destination -Name $name -Value $data -PropertyType $type -Force | Out-Null
                }
                Write-Host "    Copied value: $name" -ForegroundColor Gray
            } catch {
                Write-Host "    Failed to copy value: $name - $_" -ForegroundColor Yellow
            }
        }
        Write-Host "  ✓ Completed: $($Section.Description)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ✗ Failed: $($Section.Description) - $_" -ForegroundColor Red
        return $false
    }
}

function Copy-RegistryToDefaultPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [switch]$FilterPersonalData
    )
    try {
        if (-not (Test-Path $DestinationPath)) {
            New-Item -Path $DestinationPath -Force | Out-Null
        }
        $props = Get-ItemProperty -Path $SourcePath
        $names = $props \| Get-Member -MemberType NoteProperty \| Select-Object -ExpandProperty Name
        foreach ($name in $names) {
            if ($FilterPersonalData -and $name -match '(Email|UserName|DesktopWallpaper)') {
                Write-Host "    Skipped personal data: $name" -ForegroundColor Yellow
                continue
            }
            $value = $props.$name
            Set-ItemProperty -Path $DestinationPath -Name $name -Value $value -Force
            Write-Host "    Copied property: $name" -ForegroundColor Gray
        }
        return $true
    } catch {
        Write-Host "    Error copying registry from $SourcePath to $DestinationPath - $_" -ForegroundColor Red
        return $false
    }
}

function Get-ProfileTemplateSections {
    [CmdletBinding()]
    param()
    @(
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Description = "Explorer Advanced Settings (taskbar, file extensions, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\Control Panel\Desktop"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Desktop"; Description = "Desktop and screensaver settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\Control Panel\Keyboard"; Destination = "HKU:\DEFAULT_TEMPLATE\Control Panel\Keyboard"; Description = "Keyboard settings (NumLock, etc.)"; FilterPersonalData = $false },
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Description = "Content delivery and privacy settings"; FilterPersonalData = $true },
        @{ Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Destination = "HKU:\DEFAULT_TEMPLATE\Software\Microsoft\Windows\CurrentVersion\Explorer"; Description = "Explorer recent items settings"; FilterPersonalData = $true; CopySpecificValues = @('ShowRecent','ShowFrequent') }
    )
}

function Copy-ProfileTemplateRegistry {
    [CmdletBinding()]
    param()
    $sections = Get-ProfileTemplateSections
    $total    = $sections.Count
    $success  = 0
    Write-Host "[TEMPLATE] Processing $($total) registry sections..." -ForegroundColor Cyan
    foreach ($sec in $sections) {
        Write-Host "  Processing: $($sec.Description)" -ForegroundColor Gray
        if ($sec.CopySpecificValues) {
            $ok = Copy-SpecificRegistryValues -Section $sec
        } else {
            $ok = Copy-RegistryToDefaultPath -SourcePath $sec.Source -DestinationPath $sec.Destination -FilterPersonalData:$sec.FilterPersonalData
        }
        if ($ok) { $success++ }
    }
    return ($success -eq $total)
}

function Invoke-ProfileTemplate {
    [CmdletBinding()]
    param()
    if (-not (Mount-DefaultUserHive)) {
        Write-Host "[TEMPLATE] Aborting: unable to mount hive" -ForegroundColor Red
        return $false
    }
    try {
        $allGood = Copy-ProfileTemplateRegistry
        if ($allGood) {
            Write-Host "[TEMPLATE] Profile templating completed successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[TEMPLATE] Profile templating completed with some errors" -ForegroundColor Yellow
            return $false
        }
    } finally {
        Dismount-DefaultUserHive
    }
}

Export-ModuleMember -Function Mount-DefaultUserHive,Dismount-DefaultUserHive,Copy-SpecificRegistryValues,Copy-RegistryToDefaultPath,Get-ProfileTemplateSections,Copy-ProfileTemplateRegistry,Invoke-ProfileTemplate
