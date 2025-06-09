# =============================================================================
# WINDOWS CUSTOMIZATION TOOLKIT - SHARED FUNCTIONS
# =============================================================================

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Type,
        [switch]$Force
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
            Write-Host "[REGISTRY] Created path: $Path" -ForegroundColor Green
        }
        
        if ($Force) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        } else {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        }
        
        Write-Host "[REGISTRY] Set $Path\$Name = $Value ($Type)" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "[REGISTRY ERROR] Failed to set $Path\$Name = $Value : $_" -ForegroundColor Red
        return $false
    }
}

function Remove-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        if (Test-Path $Path -PathType Container) {
            if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $Path -Name $Name -Force
                Write-Host "[REGISTRY] Removed value: $Path\$Name" -ForegroundColor Yellow
            } else {
                Write-Host "[REGISTRY] Value not found (already removed): $Path\$Name" -ForegroundColor Gray
            }
        } else {
            Write-Host "[REGISTRY] Key not found for value: $Path\$Name" -ForegroundColor Gray
        }
        return $true
    } catch {
        Write-Host "[REGISTRY ERROR] Failed to remove value $Path\$Name : $_" -ForegroundColor Red
        return $false
    }
}

function Remove-RegistryKey {
    param([Parameter(Mandatory)][string]$Path)
    
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force
            Write-Host "[REGISTRY] Removed key: $Path" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "[REGISTRY] Key not found (already removed): $Path" -ForegroundColor Gray
            return $true
        }
    } catch {
        Write-Host "[REGISTRY ERROR] Failed to remove key $Path : $_" -ForegroundColor Red
        return $false
    }
}

function Stop-ServiceSafely {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [string]$DisplayName = $ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Stop-Service $ServiceName -WarningAction SilentlyContinue -ErrorAction Stop
                Write-Host "[SERVICE] Stopped: $DisplayName" -ForegroundColor Yellow
            } else {
                Write-Host "[SERVICE] Already stopped: $DisplayName" -ForegroundColor Gray
            }
            return $true
        } else {
            Write-Host "[SERVICE] Not found: $DisplayName (may not exist in this Windows edition)" -ForegroundColor Gray
            return $true
        }
    } catch {
        Write-Host "[SERVICE ERROR] Failed to stop $DisplayName : $_" -ForegroundColor Red
        return $false
    }
}

function Set-ServiceStartupTypeSafely {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [string]$StartupType = "Disabled",
        [string]$DisplayName = $ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service $ServiceName -StartupType $StartupType -ErrorAction Stop
            Write-Host "[SERVICE] Set $DisplayName startup type to: $StartupType" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[SERVICE] Not found: $DisplayName (may not exist in this Windows edition)" -ForegroundColor Gray
            return $true
        }
    } catch {
        Write-Host "[SERVICE ERROR] Failed to set $DisplayName startup type: $_" -ForegroundColor Red
        return $false
    }
}
