<#
.SYNOPSIS
Enhanced BGInfo deployment script using reliable startup folder approach

.DESCRIPTION
A script that downloads, installs and configures BGInfo using the proven startup folder method.
This approach is more reliable than registry-based autostart for BGInfo.

.NOTES
File Name:     ZZZ-ApplyBGInfo.ps1
Enhanced:      Based on proven NinjaOne approach with local repo file checking
PowerShell:    Version 5.1 or later
Requires:      -RunAsAdministrator
OS Support:    Windows 10/11, Windows Server 2016+
#>

## Determine script and repo directory paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path $ScriptRoot -Parent

## Variables
$bgInfoFolder = "C:\BGInfo"
$bgInfoExecutable = "$bgInfoFolder\Bginfo64.exe"

# Local repo paths (check wallpaper folder first)
$localWallpaperFolder = Join-Path $RepoRoot 'wallpaper'
$localBGInfoZip = Join-Path $localWallpaperFolder 'BGInfo.zip'
$localBGInfoExe = Join-Path $localWallpaperFolder 'Bginfo64.exe'

# Download URL
$bgInfoUrl = "https://download.sysinternals.com/files/BGInfo.zip"

# Startup folder path for all users
$startupFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$startupShortcut = "$startupFolder\BGInfo.lnk"

# Formatting variables
$global:currenttime = Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime = Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## Functions

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-Shortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][String]$Path,
        [Parameter(Mandatory)][String]$Target,
        [Parameter()][String]$Arguments,
        [Parameter()][String]$WorkingDir,
        [Parameter()][String]$IconPath
    )
    
    try {
        Write-Host "# Creating BGInfo startup shortcut..." -foregroundcolor $foregroundColor2
        $ShellObject = New-Object -ComObject ("WScript.Shell")
        $Shortcut = $ShellObject.CreateShortcut($Path)
        $Shortcut.TargetPath = $Target
        if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir }
        if ($Arguments) { $Shortcut.Arguments = $Arguments }
        if ($IconPath) { $Shortcut.IconLocation = $IconPath }
        $Shortcut.Save()

        if (Test-Path $Path) {
            Write-Host "  [OK] Startup shortcut created: $Path" -foregroundcolor $foregroundColor1
            return $true
        } else {
            Write-Host "  [ERROR] Failed to create shortcut" -foregroundcolor $foregroundColor3
            return $false
        }
    } catch {
        Write-Host "  [ERROR] Shortcut creation failed: $_" -foregroundcolor $foregroundColor3
        return $false
    }
}

function Get-BGInfoExecutable {
    [CmdletBinding()]
    param()
    
    Write-Host ($writeEmptyLine + "# Obtaining BGInfo executable..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
    
    # Check for local executable first
    if (Test-Path $localBGInfoExe) {
        Write-Host "# Found local BGInfo executable: $localBGInfoExe" -foregroundcolor $foregroundColor2
        Copy-Item -Path $localBGInfoExe -Destination $bgInfoExecutable -Force
        Write-Host "  [OK] Local BGInfo executable copied" -foregroundcolor $foregroundColor1
        return $true
    }
    
    # Check for local ZIP file
    if (Test-Path $localBGInfoZip) {
        Write-Host "# Found local BGInfo ZIP: $localBGInfoZip" -foregroundcolor $foregroundColor2
        Copy-Item -Path $localBGInfoZip -Destination "$bgInfoFolder\BGInfo.zip" -Force
        Expand-Archive -LiteralPath "$bgInfoFolder\BGInfo.zip" -DestinationPath $bgInfoFolder -Force
        Remove-Item "$bgInfoFolder\BGInfo.zip" -Force -ErrorAction SilentlyContinue
        Remove-Item "$bgInfoFolder\Eula.txt" -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Local BGInfo ZIP extracted" -foregroundcolor $foregroundColor1
        return $true
    }
    
    # Download from web as fallback
    Write-Host "# No local BGInfo found, downloading from web..." -foregroundcolor $foregroundColor2
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $bgInfoUrl -Destination "$bgInfoFolder\BGInfo.zip"
        } catch {
            Invoke-WebRequest -Uri $bgInfoUrl -OutFile "$bgInfoFolder\BGInfo.zip" -UseBasicParsing
        }
        
        Expand-Archive -LiteralPath "$bgInfoFolder\BGInfo.zip" -DestinationPath $bgInfoFolder -Force
        Remove-Item "$bgInfoFolder\BGInfo.zip" -Force -ErrorAction SilentlyContinue
        Remove-Item "$bgInfoFolder\Eula.txt" -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] BGInfo downloaded and extracted" -foregroundcolor $foregroundColor1
        return $true
        
    } catch {
        Write-Host "  [ERROR] Failed to download BGInfo: $_" -foregroundcolor $foregroundColor3
        return $false
    }
}

function Create-MinimalBGInfoConfig {
    [CmdletBinding()]
    param()
    
    Write-Host "# Creating minimal BGInfo configuration..." -foregroundcolor $foregroundColor2
    
    try {
        # Create a minimal config by running BGInfo interactively once, then saving custom config
        $configPath = "$bgInfoFolder\Minimal.bgi"
        
        # First run BGInfo to let it create its initial setup
        $process = Start-Process -FilePath $bgInfoExecutable -ArgumentList "/accepteula" -PassThru -WindowStyle Normal
        
        # Wait for user to customize and close BGInfo
        Write-Host "  [INFO] BGInfo will open - please:" -foregroundcolor $foregroundColor2
        Write-Host "    1. REMOVE unwanted fields (right-click to delete)" -foregroundcolor $foregroundColor2
        Write-Host "    2. Keep only: Computer Name, IP Address, OS Version" -foregroundcolor $foregroundColor2
        Write-Host "    3. Click 'Apply' when done" -foregroundcolor $foregroundColor2
        Write-Host "    4. BGInfo will close and save your settings" -foregroundcolor $foregroundColor2
        
        # Wait for the process to complete
        $process.WaitForExit()
        
        Write-Host "  [OK] Minimal BGInfo configuration created" -foregroundcolor $foregroundColor1
        return $true
        
    } catch {
        Write-Host "  [ERROR] Failed to create BGInfo configuration: $_" -foregroundcolor $foregroundColor3
        return $false
    }
}
function Register-BGInfoStartup {
    [CmdletBinding()]
    param()
    
    Write-Host ($writeEmptyLine + "# Setting up BGInfo autostart..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
    
    # Remove any existing BGInfo shortcuts
    if (Test-Path $startupShortcut) {
        Remove-Item $startupShortcut -Force -ErrorAction SilentlyContinue
        Write-Host "# Removed existing BGInfo startup shortcut" -foregroundcolor $foregroundColor2
    }
    
    # Remove any existing registry entries
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $regEntries = @("BGInfo", "BgInfo", "bginfo")
    foreach ($entry in $regEntries) {
        if (Get-ItemProperty -Path $regPath -Name $entry -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $regPath -Name $entry -Force -ErrorAction SilentlyContinue
            Write-Host "# Removed existing registry entry: $entry" -foregroundcolor $foregroundColor2
        }
    }
    
    # Create startup shortcut with saved configuration
    $arguments = "/timer:0 /silent"  # Uses saved config automatically
    $success = New-Shortcut -Path $startupShortcut -Target $bgInfoExecutable -Arguments $arguments
    
    if ($success) {
        Write-Host ($writeEmptyLine + "# BGInfo startup configured successfully" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1
        return $true
    } else {
        Write-Host ($writeEmptyLine + "# Failed to configure BGInfo startup" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3
        return $false
    }
}

function Test-BGInfoExecution {
    [CmdletBinding()]
    param()
    
    Write-Host ($writeEmptyLine + "# Testing BGInfo execution with minimal config..." + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2
    
    try {
        # Run BGInfo with the saved configuration
        Start-Process -FilePath $bgInfoExecutable -ArgumentList "/timer:0 /silent" -Wait -WindowStyle Hidden
        Write-Host "  [OK] BGInfo executed successfully with minimal display" -foregroundcolor $foregroundColor1
        return $true
    } catch {
        Write-Host "  [ERROR] BGInfo execution failed: $_" -foregroundcolor $foregroundColor3
        return $false
    }
}

## Main Script Execution

# Check if PowerShell is running as Administrator
if (-not (Test-Administrator)) {
    Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Write script started
Write-Host ($writeEmptyLine + "# Enhanced BGInfo deployment script started" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine

# Create BGInfo folder
try {
    if (!(Test-Path -Path $bgInfoFolder)) {
        New-Item -ItemType Directory -Force -Path $bgInfoFolder | Out-Null
        Write-Host ($writeEmptyLine + "# BGInfo folder created at $bgInfoFolder" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    } else {
        Write-Host ($writeEmptyLine + "# BGInfo folder already exists at $bgInfoFolder" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    }
} catch {
    Write-Host ($writeEmptyLine + "# Failed to create BGInfo folder: $_" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Get BGInfo executable
$executableSuccess = Get-BGInfoExecutable
if (-not $executableSuccess) {
    Write-Host ($writeEmptyLine + "# Failed to obtain BGInfo executable" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Verify executable exists
if (-not (Test-Path $bgInfoExecutable)) {
    Write-Host ($writeEmptyLine + "# BGInfo executable not found at $bgInfoExecutable" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Create minimal configuration
$configSuccess = Create-MinimalBGInfoConfig
if (-not $configSuccess) {
    Write-Host ($writeEmptyLine + "# Failed to create minimal BGInfo configuration" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Register BGInfo for startup
$startupSuccess = Register-BGInfoStartup
if (-not $startupSuccess) {
    Write-Host ($writeEmptyLine + "# Failed to configure BGInfo startup" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Test BGInfo execution
$testSuccess = Test-BGInfoExecution
if (-not $testSuccess) {
    Write-Host ($writeEmptyLine + "# BGInfo test execution failed" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor3 $writeEmptyLine
    exit 1
}

# Script completed successfully
Write-Host ($writeEmptyLine + "# Enhanced BGInfo deployment completed successfully!" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine
Write-Host "# BGInfo executable: $bgInfoExecutable" -foregroundcolor $foregroundColor1
Write-Host "# Startup shortcut: $startupShortcut" -foregroundcolor $foregroundColor1
Write-Host "# BGInfo will run automatically at startup for all users" -foregroundcolor $foregroundColor1
Write-Host ($writeEmptyLine + "# BGInfo is now active on your desktop with system information overlay" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor1 $writeEmptyLine
