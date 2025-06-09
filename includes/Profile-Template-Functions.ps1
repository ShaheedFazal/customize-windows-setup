# ============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - DEFAULT PROFILE FUNCTIONS
# ============================================================================

function Mount-DefaultUserHive {
    [CmdletBinding()]
    param()
    try {
        $defaultProfilePath = "C:\\Users\\Default\\NTUSER.DAT"
        $mountPoint = "HKEY_USERS\\DEFAULT_TEMPLATE"

        if (!(Test-Path $defaultProfilePath)) {
            throw "Default user profile not found: $defaultProfilePath"
        }

        $result = reg load $mountPoint $defaultProfilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
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
        $mountPoint = "HKEY_USERS\\DEFAULT_TEMPLATE"
        if (Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -like '*DEFAULT_TEMPLATE' }) {
            $result = reg unload $mountPoint 2>&1
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
        Copy-Item $source $backup -Recurse -Force
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
        $dest = 'C:\\Users\\Default'
        if (Test-Path $backup) {
            Copy-Item $backup $dest -Recurse -Force
            Write-Host "[TEMPLATE] Restored default profile from backup" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[TEMPLATE ERROR] Failed to restore default profile: $_" -ForegroundColor Red
    }
}

function Copy-RegistryToDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [switch]$FilterPersonalData
    )
    try {
        if (!(Test-Path $SourcePath)) {
            Write-Host "[TEMPLATE] Source path not found: $SourcePath" -ForegroundColor Yellow
            return $false
        }
        $result = reg copy $SourcePath $DestinationPath /s /f 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[TEMPLATE] Copied $SourcePath to default profile" -ForegroundColor Green
            if ($FilterPersonalData) {
                Filter-RegistrySection -KeyPath $DestinationPath | Out-Null
                Write-Host "[TEMPLATE] Applied personal data filtering" -ForegroundColor Green
            }
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

function Test-SafeForTemplating {
    [CmdletBinding()]
    param()
    return (Test-TemplatingRequirements)
}

function Invoke-ProfileTemplating {
    [CmdletBinding()]
    param()

    if (-not (Test-SafeForTemplating)) { return }

    if (-not (Backup-DefaultProfile)) { return }

    if (-not (Mount-DefaultUserHive)) { return }
    try {
        $destHive = 'HKEY_USERS\\DEFAULT_TEMPLATE'
        $sections = @(
            @{ Source = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced'; Destination = "$destHive\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced"; Filter = $true },
            @{ Source = 'HKCU:\\Control Panel\\Desktop'; Destination = "$destHive\\Control Panel\\Desktop"; Filter = $true },
            @{ Source = 'HKCU:\\Control Panel\\Keyboard'; Destination = "$destHive\\Control Panel\\Keyboard"; Filter = $false },
            @{ Source = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search'; Destination = "$destHive\\Software\\Microsoft\\Windows\\CurrentVersion\\Search"; Filter = $true },
            @{ Source = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\AutoplayHandlers'; Destination = "$destHive\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\AutoplayHandlers"; Filter = $false },
            @{ Source = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager'; Destination = "$destHive\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager"; Filter = $false }
        )
        foreach ($section in $sections) {
            Copy-RegistryToDefault -SourcePath $section.Source -DestinationPath $section.Destination -FilterPersonalData:$section.Filter | Out-Null
        }
    }
    finally {
        Dismount-DefaultUserHive | Out-Null
    }
}

