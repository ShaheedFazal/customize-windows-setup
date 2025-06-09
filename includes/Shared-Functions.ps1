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

function New-LocalUserAccount {
    param(
        [Parameter(Mandatory)][string]$AccountType,  # "Standard" or "Administrator"
        [string]$PromptText = "Enter a user name for the new account"
    )

    try {
        $username = Read-Host $PromptText

        # Password collection with validation
        do {
            $pw1 = Read-Host 'Enter password' -AsSecureString
            $pw2 = Read-Host 'Confirm password' -AsSecureString

            # Convert to plain text for comparison
            $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1))
            $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2))

            if ($plain1 -ne $plain2) {
                Write-Host "[ACCOUNT] Passwords do not match. Please try again." -ForegroundColor Yellow
            }
        } until ($plain1 -eq $plain2)

        # Create the user account
        net user $username $plain1 /add | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create user account"
        }

        # Add to appropriate group
        if ($AccountType -eq "Administrator") {
            net localgroup Administrators $username /add | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to add user to Administrators group"
            }
            Write-Host "[ACCOUNT] Created local administrator account: $username" -ForegroundColor Green
        } else {
            net localgroup Users $username /add | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to add user to Users group"
            }
            Write-Host "[ACCOUNT] Created standard user account: $username" -ForegroundColor Green
        }

        # Clear password variables
        $plain1 = $null
        $plain2 = $null

        return $username

    } catch {
        Write-Host "[ACCOUNT ERROR] Failed to create $AccountType account: $_" -ForegroundColor Red
        return $null
    }
}

function Test-LocalAccountExists {
    param(
        [Parameter(Mandatory)][string]$Username
    )

    try {
        $account = Get-CimInstance Win32_UserAccount -Filter "Name='$Username' AND LocalAccount=true" -ErrorAction SilentlyContinue
        if ($account) {
            Write-Host "[ACCOUNT] Local account exists: $Username" -ForegroundColor Gray
            return $true
        } else {
            Write-Host "[ACCOUNT] Local account not found: $Username" -ForegroundColor Gray
            return $false
        }
    } catch {
        Write-Host "[ACCOUNT ERROR] Failed to check account existence: $_" -ForegroundColor Red
        return $false
    }
}

function Get-LocalAccountCount {
    param(
        [string[]]$ExcludeBuiltIns = @('Administrator','DefaultAccount','Guest','WDAGUtilityAccount')
    )

    try {
        $localAccounts = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=true AND Disabled=false" -ErrorAction SilentlyContinue
        $filteredAccounts = $localAccounts | Where-Object {
            $_.Name -notin $ExcludeBuiltIns
        }

        $count = ($filteredAccounts | Measure-Object).Count
        Write-Host "[ACCOUNT] Found $count non-built-in local accounts" -ForegroundColor Gray

        return @{
            Count = $count
            Accounts = $filteredAccounts
        }

    } catch {
        Write-Host "[ACCOUNT ERROR] Failed to enumerate local accounts: $_" -ForegroundColor Red
        return @{ Count = 0; Accounts = @() }
    }
}
