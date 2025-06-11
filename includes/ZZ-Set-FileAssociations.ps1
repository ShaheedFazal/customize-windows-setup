#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies standard configurations for a workgroup computer.
.DESCRIPTION
    This script performs two main actions:
    1. Sets default file associations using a 'WorkgroupDefaults.xml' file.
    2. Configures a Microsoft Edge policy to stop it from asking to be the default browser.

    The script looks for the XML file in its own directory.
    This script MUST be run with Administrator privileges.
#>

param(
    [string]$SetUserFtaDir = 'C:\Scripts'
)

Write-Host "Starting system configuration..." -ForegroundColor Cyan

# Ensure TLS 1.2 for downloads
if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

function Download-File {
    param([string]$Url, [string]$Path)
    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            if ($i -eq $maxRetries) { return $false }
            Start-Sleep -Seconds (2 * $i)
        }
    }
    return $false
}

# Ensure SetUserFTA is available for file association changes
if (-not (Test-Path $SetUserFtaDir)) {
    New-Item -ItemType Directory -Path $SetUserFtaDir | Out-Null
}
$arch        = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$setUserFtaUrl = "https://setuserfta.com/downloads/SetUserFTA_$arch.zip"
$setUserFtaZip  = Join-Path $env:TEMP "SetUserFTA_$arch.zip"
$setUserFtaPath = Join-Path $SetUserFtaDir 'SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "Downloading SetUserFTA..." -ForegroundColor Cyan
    if (Download-File -Url $setUserFtaUrl -Path $setUserFtaZip) {
        try {
            Expand-Archive -Path $setUserFtaZip -DestinationPath $SetUserFtaDir -Force
            Remove-Item $setUserFtaZip -ErrorAction SilentlyContinue

            $executable = Get-ChildItem -Path $SetUserFtaDir -Filter 'SetUserFTA*.exe' -Recurse | Where-Object { $_.Name -match $arch } | Select-Object -First 1
            if (-not $executable) {
                $executable = Get-ChildItem -Path $SetUserFtaDir -Filter 'SetUserFTA*.exe' -Recurse | Select-Object -First 1
            }
            if ($executable) {
                Copy-Item $executable.FullName $setUserFtaPath -Force
                Write-Host "[OK] SetUserFTA extracted to $setUserFtaPath" -ForegroundColor Green
            } else {
                Write-Warning "SetUserFTA executable not found after extraction"
                Write-Log "SetUserFTA executable missing after extraction"
            }
        } catch {
            Write-Host "[ERROR] Failed to extract SetUserFTA: $_" -ForegroundColor Red
            Write-Log "SetUserFTA extraction failed: $_"
        }
    } else {
        Write-Host "[ERROR] SetUserFTA download failed" -ForegroundColor Red
        Write-Log "SetUserFTA download failed from $setUserFtaUrl"
    }
}

# Verify SetUserFTA exists before continuing
if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "[ERROR] SetUserFTA.exe not found at $setUserFtaPath" -ForegroundColor Red
    Write-Host "Please download it manually from https://setuserfta.com and place it in the folder." -ForegroundColor Yellow
    return
}

# --- Action 1: Apply Default File Associations ---
try {
    Write-Host "`n[1/2] Applying default file associations..." -ForegroundColor White

    # Get the directory where this script is located.
    $scriptDirectory = $PSScriptRoot

    # Define the expected name of the XML configuration file.
    $xmlFileName = "AppAssoc.xml"
    $xmlPath = Join-Path $scriptDirectory $xmlFileName

    # Check if the XML file actually exists.
    if (-not (Test-Path $xmlPath)) {
        throw "Configuration file not found. Make sure '$xmlFileName' is in the same folder as this script."
    }

    Write-Host " - Found configuration file at: $xmlPath" -ForegroundColor Green
    Dism.exe /Online /Import-DefaultAppAssociations:$xmlPath
    Write-Host " - Successfully applied new default file associations." -ForegroundColor Green
    Write-Host "   (Changes will take effect for existing users on their next login)"

    # Apply associations immediately for the current user using Set-FileAssociation
    try {
        if (-not (Get-Command Set-FileAssociation -ErrorAction SilentlyContinue)) {
            $shared = Join-Path $scriptDirectory 'Shared-Functions.ps1'
            if (Test-Path $shared) { . $shared }
        }
        $xmlContent = [xml](Get-Content -Path $xmlPath)
        foreach ($assoc in $xmlContent.DefaultAssociations.Association) {
            Set-FileAssociation -ExtensionOrProtocol $assoc.Identifier -ProgId $assoc.ProgId -SetUserFtaPath $setUserFtaPath
        }
        Write-Host " - Current user associations configured." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set associations for current user: $_"
    }

}
catch {
    Write-Error "An error occurred during file association setup: $_"
}


# --- Action 2: Configure Microsoft Edge Policy ---
try {
    Write-Host "`n[2/2] Configuring Microsoft Edge policies..." -ForegroundColor White

    # Define the path in HKEY_LOCAL_MACHINE to apply the policy to ALL users.
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    # Check if the 'Edge' key exists. If not, create it.
    if (-not (Test-Path $edgePolicyPath)) {
        Write-Host " - Edge policy key not found. Creating it now..." -ForegroundColor Yellow
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    # Set the registry value to disable the default browser check.
    # Name: DefaultBrowserSettingEnabled
    # Type: DWORD (32-bit)
    # Value: 0
    New-ItemProperty -Path $edgePolicyPath -Name "DefaultBrowserSettingEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

    Write-Host " - Successfully set Edge policy to prevent default browser prompts." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred during Edge policy configuration: $_"
}


# --- Finish ---
Write-Host "`nConfiguration complete." -ForegroundColor Cyan