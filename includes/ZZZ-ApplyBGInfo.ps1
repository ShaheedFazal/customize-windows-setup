<#
.SYNOPSIS
Enhanced BGInfo deployment script that checks for local repo files before downloading

.DESCRIPTION
A script used to download, install, and configure the latest version of BGInfo on Windows systems.
This enhanced version first checks for BGInfo files in the local repository structure before downloading.

This script will do all of the following:
- Check if PowerShell is running as Administrator, otherwise exit the script
- Create a BGInfo folder on the C: drive if it doesn't already exist; otherwise, delete its contents
- Check for local BGInfo files in repo structure, or download latest BGInfo software to C:\BGInfo
- Check for local logon.bgi file in repo, or download it to C:\BGInfo
- Create BGInfo registry key for AutoStart
- Run BGInfo

.NOTES
File Name:     ZZZ-ApplyBGInfo.ps1
Created:       Enhanced version based on Wim Matthyssen's original
Last Modified: Current date
PowerShell:    Version 5.1 or later
Requires:      -RunAsAdministrator
OS Support:    Windows Server 2016, 2019, 2022, 2025 and Windows 10/11
Enhanced:      Added local repo file checking before download fallback
#>

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Determine script and repo directory paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path $ScriptRoot -Parent

## Variables
$bgInfoFolder = "C:\Wallpaper"
$bgInfoFolderContent = "$bgInfoFolder\BGInfo*"

# Local repo paths (check wallpaper folder first)
$localWallpaperFolder = Join-Path $RepoRoot 'wallpaper'
$localBGInfoZip = Join-Path $localWallpaperFolder 'BGInfo.zip'
$localBGInfoExe = Join-Path $localWallpaperFolder 'Bginfo64.exe'
$localWallpaperBgi = Join-Path $localWallpaperFolder 'WallpaperSettings.bgi'

# Download URLs (fallback if local files not found)
$bgInfoUrl = "https://download.sysinternals.com/files/BGInfo.zip"
$wallpaperBgiUrl = "https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/wallpaper/WallpaperSettings.bgi"

# Target paths
$bgInfoZip = "$bgInfoFolder\BGInfo.zip"
$bgInfoEula = "$bgInfoFolder\Eula.txt"
$wallpaperBgiZip = "$bgInfoFolder\WallpaperSettings.zip"

# Registry settings
$bgInfoRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$bgInfoRegKey = "BGInfo"
$bgInfoRegKeyValue = "C:\Wallpaper\Bginfo64.exe C:\Wallpaper\WallpaperSettings.bgi /timer:0 /nolicprompt"

# Formatting variables
$global:currenttime = Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime = Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Functions

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Copy-LocalBGInfoFiles {
    [CmdletBinding()]
    param()
    
    $configFound = $false
    $executableFound = $false
    
    Write-Host ($writeEmptyLine + "# Checking for local BGInfo files in wallpaper folder..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
    
    # Check if we have a local BGInfo executable
    if (Test-Path $localBGInfoExe) {
        Write-Host "# Found local BGInfo executable: $localBGInfoExe" -foregroundcolor $foregroundColor2
        Copy-Item -Path $localBGInfoExe -Destination "$bgInfoFolder\Bginfo64.exe" -Force
        $executableFound = $true
    }
    elseif (Test-Path $localBGInfoZip) {
        Write-Host "# Found local BGInfo ZIP: $localBGInfoZip" -foregroundcolor $foregroundColor2
        Copy-Item -Path $localBGInfoZip -Destination $bgInfoZip -Force
        
        # Extract the ZIP file
        Expand-Archive -LiteralPath $bgInfoZip -DestinationPath $bgInfoFolder -Force
        Remove-Item $bgInfoZip -Force -ErrorAction SilentlyContinue
        Remove-Item $bgInfoEula -Force -ErrorAction SilentlyContinue
        $executableFound = $true
    }
    
    # Check for local WallpaperSettings.bgi file
    if (Test-Path $localWallpaperBgi) {
        Write-Host "# Found local WallpaperSettings.bgi: $localWallpaperBgi" -foregroundcolor $foregroundColor2
        Copy-Item -Path $localWallpaperBgi -Destination "$bgInfoFolder\WallpaperSettings.bgi" -Force
        $configFound = $true
    }
    
    if ($configFound -or $executableFound) {
        Write-Host ($writeEmptyLine + "# Local BGInfo files copied from wallpaper folder successfully" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1
        if ($configFound) { 
            Write-Host "  ✓ Configuration file WallpaperSettings.bgi found locally" -foregroundcolor $foregroundColor1 
        }
        if ($executableFound) { 
            Write-Host "  ✓ Executable file Bginfo64.exe found locally" -foregroundcolor $foregroundColor1 
        }
    } else {
        Write-Host "# No local BGInfo files found in wallpaper folder" -foregroundcolor $foregroundColor2
    }
    
    return @{
        ConfigFound = $configFound
        ExecutableFound = $executableFound
        AnyFound = ($configFound -or $executableFound)
    }
}

function Download-BGInfoFromWeb {
    [CmdletBinding()]
    param(
        [bool]$NeedExecutable = $true,
        [bool]$NeedConfig = $true
    )
    
    try {
        Write-Host ($writeEmptyLine + "# Downloading missing BGInfo files from web..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
        
        # Ensure TLS 1.2 is used for compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Download BGInfo executable if needed
        if ($NeedExecutable -and (-not (Test-Path "$bgInfoFolder\Bginfo64.exe"))) {
            Write-Host "# Downloading BGInfo executable..." -foregroundcolor $foregroundColor2
            
            try {
                # Try BitsTransfer first
                Import-Module BitsTransfer -ErrorAction Stop
                Start-BitsTransfer -Source $bgInfoUrl -Destination $bgInfoZip
            } catch {
                # Fallback to Invoke-WebRequest
                Write-Host "# BitsTransfer failed, using Invoke-WebRequest..." -foregroundcolor $foregroundColor2
                Invoke-WebRequest -Uri $bgInfoUrl -OutFile $bgInfoZip -UseBasicParsing
            }
            
            # Extract and clean up
            Expand-Archive -LiteralPath $bgInfoZip -DestinationPath $bgInfoFolder -Force
            Remove-Item $bgInfoZip, $bgInfoEula -Force -ErrorAction SilentlyContinue
            Write-Host "  ✓ BGInfo executable downloaded and extracted" -foregroundcolor $foregroundColor1
        }
        
        # Download WallpaperSettings.bgi if needed
        if ($NeedConfig -and (-not (Test-Path "$bgInfoFolder\WallpaperSettings.bgi"))) {
            Write-Host "# Downloading WallpaperSettings.bgi configuration..." -foregroundcolor $foregroundColor2
            
            Invoke-WebRequest -Uri $wallpaperBgiUrl -OutFile "$bgInfoFolder\WallpaperSettings.bgi" -UseBasicParsing
            Write-Host "  ✓ WallpaperSettings.bgi downloaded" -foregroundcolor $foregroundColor1
        }
        
        Write-Host ($writeEmptyLine + "# Required BGInfo files obtained successfully" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1
        return $true
        
    } catch {
        Write-Host ($writeEmptyLine + "# Failed to download BGInfo files: $_" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3
        return $false
    }
}

function Test-BGInfoFiles {
    [CmdletBinding()]
    param()
    
    $required = @(
        "$bgInfoFolder\Bginfo64.exe",
        "$bgInfoFolder\WallpaperSettings.bgi"
    )
    
    foreach ($file in $required) {
        if (-not (Test-Path $file)) {
            Write-Host "# Missing required file: $file" -foregroundcolor $foregroundColor3
            return $false
        }
    }
    
    Write-Host "# All required BGInfo files are present" -foregroundcolor $foregroundColor1
    return $true
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Main Script Execution

# Check if PowerShell is running as Administrator
if (-not (Test-Administrator)) {
    Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Write script started
Write-Host ($writeEmptyLine + "# Enhanced BGInfo deployment script started" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create Wallpaper folder or clean existing BGInfo content
try {
    if (!(Test-Path -Path $bgInfoFolder)) {
        New-Item -ItemType Directory -Force -Path $bgInfoFolder | Out-Null
        Write-Host ($writeEmptyLine + "# Wallpaper folder created at $bgInfoFolder" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    } else {
        # Only remove BGInfo-related files, preserve wallpaper files
        Remove-Item -Path $bgInfoFolderContent -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host ($writeEmptyLine + "# Existing BGInfo content cleaned from wallpaper folder" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    }
} catch {
    Write-Host ($writeEmptyLine + "# Failed to create or clean wallpaper folder: $_" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Try to copy local files first, then download what's missing
$localFiles = Copy-LocalBGInfoFiles

# Determine what we need to download
$needExecutable = -not (Test-Path "$bgInfoFolder\Bginfo64.exe")
$needConfig = -not (Test-Path "$bgInfoFolder\WallpaperSettings.bgi")

if ($needExecutable -or $needConfig) {
    $downloadSuccess = Download-BGInfoFromWeb -NeedExecutable $needExecutable -NeedConfig $needConfig
    if (-not $downloadSuccess) {
        Write-Host ($writeEmptyLine + "# Failed to obtain required BGInfo files" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
        exit 1
    }
} else {
    Write-Host ($writeEmptyLine + "# All required BGInfo files are available" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1
}

# Verify all required files are present
if (-not (Test-BGInfoFiles)) {
    Write-Host ($writeEmptyLine + "# BGInfo installation incomplete - missing required files" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create BGInfo registry key for AutoStart
try {
    if (Get-ItemProperty -Path $bgInfoRegPath -Name $bgInfoRegKey -ErrorAction SilentlyContinue) {
        Write-Host ($writeEmptyLine + "# BGInfo registry key already exists" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    } else {
        New-ItemProperty -Path $bgInfoRegPath -Name $bgInfoRegKey -PropertyType String -Value $bgInfoRegKeyValue -Force | Out-Null
        Write-Host ($writeEmptyLine + "# BGInfo registry key created" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    }
} catch {
    Write-Host ($writeEmptyLine + "# Failed to create BGInfo registry key: $_" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Run BGInfo
try {
    Write-Host ($writeEmptyLine + "# Executing BGInfo..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
    Start-Process -FilePath "$bgInfoFolder\Bginfo64.exe" -ArgumentList "$bgInfoFolder\WallpaperSettings.bgi /timer:0 /nolicprompt" -NoNewWindow -Wait
    Write-Host ($writeEmptyLine + "# BGInfo executed successfully" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine
} catch {
    Write-Host ($writeEmptyLine + "# Failed to execute BGInfo: $_" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Write script completed
Write-Host ($writeEmptyLine + "# Enhanced BGInfo deployment completed successfully!" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine

if ($localFiles.ConfigFound -and $localFiles.ExecutableFound) {
    Write-Host "# Used all local BGInfo files from wallpaper folder" -foregroundcolor $foregroundColor1
} elseif ($localFiles.AnyFound) {
    Write-Host "# Used local BGInfo files from wallpaper folder + downloaded missing files" -foregroundcolor $foregroundColor1
} else {
    Write-Host "# Downloaded all BGInfo files from web sources" -foregroundcolor $foregroundColor1
}

Write-Host "# BGInfo files installed to: $bgInfoFolder" -foregroundcolor $foregroundColor1
Write-Host ($writeEmptyLine + "# BGInfo will now run automatically at startup" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine