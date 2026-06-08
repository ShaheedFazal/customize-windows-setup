# Windows Hardening Script - Original Version

This is your original script without any modifications.

```powershell
<#
.SYNOPSIS
    Applies comprehensive security hardening policies to a Windows system and then reboots.
.DESCRIPTION
    This script enhances the security posture of a Windows system by applying a set of hardening policies
    from the Harden-Windows-Security-Module and then performs a detailed hardening of Microsoft Defender settings.
    Upon successful completion, the script will automatically restart the computer to ensure all policies are applied.

    It includes a robust launcher mechanism that ensures the core logic always runs in PowerShell 7.
    It now includes a mandatory check for Administrator privileges and isolates potentially problematic
    components for more resilient execution.
.PARAMETER IsElevatedInPs7
    A switch parameter used internally by the script to prevent an infinite re-launch loop.
    This parameter should not be used when calling the script manually.
.PARAMETER NoReboot
    A switch parameter that, if present, will prevent the script from automatically restarting the computer.
    This is useful for testing or chained script scenarios.
.REQUIREMENTS
    - The script must be run with administrative privileges (Run as Administrator or as SYSTEM).
    - PowerShell 7 must be installed in its default location (`C:\Program Files\PowerShell\7`).
.USAGE
    Right-click the script and select "Run with PowerShell" if you have administrative rights,
    or open an administrative PowerShell prompt and execute it:
    .\YourScriptName.ps1

    To run without an automatic reboot:
    .\YourScriptName.ps1 -NoReboot
.NOTES
    Version: 2.8
    Author: Your Name
    Date: 2025-07-11
#>

# =================================================================================
# SCRIPT PARAMETERS
# =================================================================================
param (
    # This switch is used internally by the script to prevent an infinite loop.
    [switch]$IsElevatedInPs7,

    # This allows for testing or running the script without forcing a restart.
    [switch]$NoReboot
)

# =================================================================================
# PRE-FLIGHT CHECKS
# =================================================================================

# --- Step 1: MANDATORY - Check for Administrator Privileges ---
Write-Host "Checking for administrator privileges..."
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object System.Security.Principal.WindowsPrincipal $currentUser).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "FATAL: This script must be run with Administrator privileges." -ForegroundColor Red
    Write-Host "Please re-run from an elevated PowerShell prompt (Run as Administrator)." -ForegroundColor Red
    exit 1001
} else {
    Write-Host "Success: Running with Administrator privileges." -ForegroundColor Green
}


# =================================================================================
# LAUNCHER & VERSION CHECK
# =================================================================================

# --- Step 2: Check PowerShell Version and Re-launch if Necessary ---
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $IsElevatedInPs7.IsPresent) {
    Write-Host "PowerShell 5.1 detected. Re-launching script in PowerShell 7 for compatibility..." -ForegroundColor Yellow
    $pwsh7_executable = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"

    if (-not (Test-Path $pwsh7_executable)) {
        Write-Host "FATAL: PowerShell 7 not found at '$pwsh7_executable'. Please ensure it is installed." -ForegroundColor Red
        exit 1
    }

    $currentScriptPath = $MyInvocation.MyCommand.Path

    # Forward the -NoReboot switch to the new process if it was used.
    $rebootSwitch = if ($NoReboot.IsPresent) { "-NoReboot" } else { "" }

    try {
        $processArgs = "-ExecutionPolicy Bypass -File `"$currentScriptPath`" -IsElevatedInPs7 $rebootSwitch"
        Write-Host "Starting new process: $pwsh7_executable $processArgs" -ForegroundColor Cyan
        Start-Process -FilePath $pwsh7_executable -ArgumentList $processArgs -Wait -NoNewWindow -ErrorAction Stop
        Write-Host "PowerShell 7 process has completed. Exiting PowerShell 5.1 session." -ForegroundColor Yellow
        exit $LASTEXITCODE
    }
    catch {
        Write-Host "FATAL: Failed to re-launch script in PowerShell 7." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# =================================================================================
# CORE HARDENING LOGIC
# =================================================================================

# This creates a detailed log file of the entire script's output.
$logPath = "C:\ProgramData\SuperOps\Logs"
if (-not (Test-Path $logPath)) { New-Item -Path $logPath -ItemType Directory -Force }
$logFile = Join-Path $logPath "Windows-Hardening-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $logFile -Append

Write-Host "Successfully running in PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Host "Proceeding with security hardening..."

# --- Step 3: Ensure Module is available ---
try {
    Write-Host "Ensuring 'Harden-Windows-Security-Module' is installed and up-to-date..."
    Install-Module -Name 'Harden-Windows-Security-Module' -Force -Scope AllUsers -ErrorAction Stop
    Import-Module -Name 'Harden-Windows-Security-Module' -Force -ErrorAction Stop
    Write-Host "Module installed and imported successfully."
}
catch {
    Write-Host "FATAL ERROR: Could not install or import the Harden-Windows-Security-Module." -ForegroundColor Red
    Write-Host ($_.Exception.Message) -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# --- Step 4: Apply Standard Hardening Policies ---
try {
    Write-Host "Applying all standard security baselines..."
    $standardCategories = @(
        "MicrosoftSecurityBaselines", "Microsoft365AppsSecurityBaselines",
        "BitLockerSettings", "DeviceGuard", "TLSSecurity",
        "UserAccountControl", "WindowsFirewall", "OptionalWindowsFeatures", "WindowsNetworking",
        "MiscellaneousConfigurations", "EdgeBrowserConfigurations", "CertificateCheckingCommands"
    )
    Protect-WindowsSecurity -Categories $standardCategories -Verbose -ErrorAction Stop
    Write-Host "Standard policies applied successfully." -ForegroundColor Green
}
catch {
    Write-Host "FATAL ERROR during standard policy application:" -ForegroundColor Red
    Write-Host ($_.Exception.Message | Out-String) -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# --- Step 5: Apply Specific Policies Individually ---
try {
    Write-Host "Applying Lock Screen policy..."
    Protect-WindowsSecurity -Categories LockScreen -LockScreen_CtrlAltDel -Verbose -ErrorAction Stop
    Write-Host "Lock Screen policy applied successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to apply the Lock Screen policy. Continuing..."
    Write-Warning ($_.Exception.Message | Out-String)
}

# --- Step 6: Apply Firewall-Intensive Policies with Specific Error Handling ---
try {
    Write-Host "Applying Country IP Blocking firewall rules..."
    Protect-WindowsSecurity -Categories "CountryIPBlocking" -Verbose -ErrorAction Stop
    Write-Host "Country IP Blocking rules applied successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to apply Country IP Blocking firewall rules. This is often caused by external policies."
    Write-Warning "REASON: The error '$($_.Exception.Message)' usually means a Group Policy (GPO) or third-party security product (Antivirus/EDR) is controlling the Windows Firewall."
    Write-Warning "ACTION: Please check for conflicting security software or GPOs. The rest of the hardening script completed successfully."
}

# --- Step 7: Advanced Microsoft Defender Hardening ---
Write-Host "`n--- Starting Advanced Microsoft Defender Hardening ---" -ForegroundColor White

# 7.1: Enabling Core Protection Features
Write-Host "`n--- Step 7.1: Enabling Core Protection Features ---" -ForegroundColor White
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Write-Host "  - Real-time Monitoring: Enabled" -ForegroundColor Green
    Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop
    Write-Host "  - Behavior Monitoring: Enabled" -ForegroundColor Green
    Set-MpPreference -DisableIOAVProtection $false -ErrorAction Stop
    Write-Host "  - Internet & Attachment Scanning (IOAV): Enabled" -ForegroundColor Green
    Set-MpPreference -DisableScriptScanning $false -ErrorAction Stop
    Write-Host "  - Script Scanning (AMSI): Enabled" -ForegroundColor Green
}
catch {
    Write-Warning "A non-critical error occurred while enabling core features. The script will continue. Details: $_"
}

# 7.2: Enabling Cloud-Delivered Protection
Write-Host "`n--- Step 7.2: Enabling Cloud-Delivered Protection ---" -ForegroundColor White
try {
    Set-MpPreference -MAPSReporting Advanced -ErrorAction Stop
    Write-Host "  - Cloud-Delivered Protection (MAPS): Enabled (Advanced)" -ForegroundColor Green
    Set-MpPreference -CloudBlockLevel High -ErrorAction Stop
    Write-Host "  - Cloud Block Level: Set to High" -ForegroundColor Green
    Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Stop # 1 = Send safe samples automatically
    Write-Host "  - Automatic Sample Submission: Enabled" -ForegroundColor Green
}
catch {
    Write-Warning "A non-critical error occurred while enabling cloud protection. The script will continue. Details: $_"
}

# 7.3: Enabling Potentially Unwanted Application (PUA) Protection
Write-Host "`n--- Step 7.3: Enabling PUA Protection ---" -ForegroundColor White
try {
    # This setting corresponds to the "Block apps" checkbox
    Set-MpPreference -PUAProtection Enabled -ErrorAction Stop
    Write-Host "  - Potentially Unwanted Application (PUA) Protection: Enabled" -ForegroundColor Green
}
catch {
    Write-Warning "A non-critical error occurred while enabling PUA Protection. The script will continue. Details: $_"
}

# --- Step 7.4: Explicitly Enable All Reputation-Based Protection Features ---
Write-Host "`n--- Step 7.4: Explicitly Enabling Reputation-Based Protection ---" -ForegroundColor White
try {
    # These settings directly correspond to the toggles in the Windows Security UI.
    Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop
    Write-Host "  - Network Protection: Enabled" -ForegroundColor Green

    # Note: "Check apps and files" is enabled via the Microsoft Security Baselines in Step 4.
    # The previous attempt to set it with an explicit cmdlet was incorrect and has been removed.

    # Explicitly set the policy for blocking PUA downloads via SmartScreen for Edge.
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePolicyPath -Name "SmartScreenPuaEnabled" -Value 1 -Type DWord -Force
    Write-Host "  - SmartScreen PUA Download Blocking for Edge: Enabled via Registry" -ForegroundColor Green
}
catch {
    Write-Warning "A non-critical error occurred while enabling Reputation-Based Protection features. The script will continue. Details: $_"
}


# 7.5: Enabling Ransomware & Tamper Protection
Write-Host "`n--- Step 7.5: Enabling Ransomware & Tamper Protection ---" -ForegroundColor White
try {
    Set-MpPreference -DisableTamperProtection $false -ErrorAction SilentlyContinue
    $tamperStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -ErrorAction SilentlyContinue
    if ($tamperStatus -and $tamperStatus.TamperProtection -ge 4) { # 4=enabled, 5=enabled and managed
        Write-Host "  - Tamper Protection: Verified as Enabled." -ForegroundColor Green
    } else {
        Write-Warning "  - Tamper Protection: Could not be enabled or verified. This is expected if the device is managed by a central security solution (like Intune/Defender for Endpoint) which locks this setting."
    }
}
catch {
    Write-Warning "An unexpected error occurred while handling Tamper Protection. The script will continue. Details: $_"
}

try {
    Set-MpPreference -EnableControlledFolderAccess 2 -ErrorAction Stop # 2 = Audit Mode
    Write-Host "  - Controlled Folder Access: Enabled (Audit Mode)" -ForegroundColor Cyan
    Write-Host "    (This will log threats without blocking them. Review logs in Event Viewer before enabling full block mode.)" -ForegroundColor Gray
}
catch {
    Write-Warning "An error occurred while enabling Controlled Folder Access. The script will continue. Details: $_"
}

# 7.6: Verifying and Starting Essential Services
Write-Host "`n--- Step 7.6: Verifying and Starting Essential Services ---" -ForegroundColor White
$services = @("WinDefend", "wscsvc", "Sense")
foreach ($service in $services) {
    $serviceObject = Get-Service -Name $service -ErrorAction SilentlyContinue
    if (-not $serviceObject) {
        Write-Host "  - Service '$service' not found. Skipping. (This is normal for some Windows versions)." -ForegroundColor Gray
        continue
    }

    if ($serviceObject.StartType -eq 'Disabled') {
        Write-Warning "  - Service '$service' is Disabled. It cannot be started. This may be by design or due to a GPO."
        continue
    }

    if ($serviceObject.Status -ne "Running") {
        try {
            Start-Service -InputObject $serviceObject -ErrorAction Stop
            Write-Host "  - Successfully started service: $service" -ForegroundColor Green
        }
        catch {
            Write-Warning "  - Failed to start service '$service'. It may be stopped by Group Policy or another issue."
        }
    } else {
        Write-Host "  - Service '$service' is already running." -ForegroundColor Green
    }
}

# --- Step 8: System Restart ---
Write-Host "`nSecurity hardening script has finished." -ForegroundColor Cyan

if ($NoReboot.IsPresent) {
    Write-Host "The -NoReboot switch was used. System restart has been skipped." -ForegroundColor Yellow
    Write-Host "A restart is still required to apply all changes."
}
else {
    Write-Host "A system restart is required to apply all changes." -ForegroundColor Yellow
    Write-Host "The computer will restart in 30 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    Restart-Computer -Force
}

Stop-Transcript
exit 0
```
