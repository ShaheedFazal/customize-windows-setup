# Windows Hardening Script - With Monthly Run Control

This version includes a registry-based marker that allows the script to run once per month and exit gracefully if already run.

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

    NEW: Registry-based run control prevents re-execution within 30 days.
.PARAMETER IsElevatedInPs7
    A switch parameter used internally by the script to prevent an infinite re-launch loop.
    This parameter should not be used when calling the script manually.
.PARAMETER NoReboot
    A switch parameter that, if present, will prevent the script from automatically restarting the computer.
    This is useful for testing or chained script scenarios.
.PARAMETER Force
    A switch parameter that bypasses the 30-day run control and forces the script to run.
.REQUIREMENTS
    - The script must be run with administrative privileges (Run as Administrator or as SYSTEM).
    - PowerShell 7 must be installed in its default location (`C:\Program Files\PowerShell\7`).
.USAGE
    Right-click the script and select "Run with PowerShell" if you have administrative rights,
    or open an administrative PowerShell prompt and execute it:
    .\YourScriptName.ps1

    To run without an automatic reboot:
    .\YourScriptName.ps1 -NoReboot

    To force re-run (bypass 30-day limit):
    .\YourScriptName.ps1 -Force
.NOTES
    Version: 3.0
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
    [switch]$NoReboot,

    # This bypasses the 30-day run control
    [switch]$Force
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

# --- Step 1.5: Run-Once Check (allows monthly re-run) - Registry Based ---
# Uses Ticks (Int64) for region-independent date storage
$markerRegPath = "HKLM:\SOFTWARE\MyLocalChemist"
$markerValueName = "HardeningLastRunTicks"
$rerunIntervalDays = 30

# Ensure registry path exists
if (-not (Test-Path $markerRegPath)) {
    New-Item -Path $markerRegPath -Force | Out-Null
}

if (-not $Force.IsPresent) {
    $lastRunValue = Get-ItemProperty -Path $markerRegPath -Name $markerValueName -ErrorAction SilentlyContinue
    if ($lastRunValue -and $lastRunValue.$markerValueName) {
        try {
            # Convert ticks back to DateTime (region-independent)
            $lastRunTicks = [long]$lastRunValue.$markerValueName
            $lastRunDate = [DateTime]::new($lastRunTicks)
            $daysSinceLastRun = (New-TimeSpan -Start $lastRunDate -End (Get-Date)).Days

            if ($daysSinceLastRun -lt $rerunIntervalDays) {
                $nextAllowedDate = $lastRunDate.AddDays($rerunIntervalDays)
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "HARDENING SKIPPED - ALREADY RUN RECENTLY" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host "Last successful run: $($lastRunDate.ToString('yyyy-MM-dd HH:mm:ss')) ($daysSinceLastRun days ago)" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "This script is limited to run once every $rerunIntervalDays days" -ForegroundColor Gray
                Write-Host "to avoid unnecessary reboots and system changes." -ForegroundColor Gray
                Write-Host ""
                Write-Host "Next allowed run date: $($nextAllowedDate.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
                Write-Host "(Script will execute if triggered on or after this date)" -ForegroundColor Gray
                Write-Host ""
                Write-Host "To force immediate re-run:" -ForegroundColor Gray
                Write-Host "  - Use parameter: -Force" -ForegroundColor White
                Write-Host "  - Or delete: $markerRegPath\$markerValueName" -ForegroundColor White
                Write-Host "========================================" -ForegroundColor Cyan
                exit 0
            } else {
                Write-Host "Last run was $daysSinceLastRun days ago. Proceeding with monthly hardening..." -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Could not parse last run date. Proceeding with hardening..." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "-Force specified. Bypassing run control check..." -ForegroundColor Yellow
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

    # Forward the -NoReboot and -Force switches to the new process if used.
    $rebootSwitch = if ($NoReboot.IsPresent) { "-NoReboot" } else { "" }
    $forceSwitch = if ($Force.IsPresent) { "-Force" } else { "" }

    try {
        $processArgs = "-ExecutionPolicy Bypass -File `"$currentScriptPath`" -IsElevatedInPs7 $rebootSwitch $forceSwitch"
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
$logPath = "C:\Temp"
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

# --- Step 6.5: Re-enable Location Services (for time zone sync) ---
Write-Host "`n--- Step 6.5: Re-enabling Location Services ---" -ForegroundColor White
try {
    $locationPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
    if (Test-Path $locationPolicyPath) {
        Set-ItemProperty -Path $locationPolicyPath -Name "DisableLocation" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $locationPolicyPath -Name "DisableLocationScripting" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $locationPolicyPath -Name "DisableWindowsLocationProvider" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  - Location policy values set to enabled (0)" -ForegroundColor Green
    } else {
        Write-Host "  - Location policy path not found - no changes needed" -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Failed to configure location services. Details: $_"
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

# --- Step 7.7: Save completion marker to registry (using Ticks for region-independence) ---
Write-Host "`n--- Saving completion marker ---" -ForegroundColor White
try {
    if (-not (Test-Path $markerRegPath)) {
        New-Item -Path $markerRegPath -Force | Out-Null
    }
    # Store as Ticks (Int64) - works regardless of regional date format settings
    $currentTicks = (Get-Date).Ticks
    Set-ItemProperty -Path $markerRegPath -Name $markerValueName -Value $currentTicks -Type QWord -Force
    Write-Host "  - Completion marker saved to registry: $markerRegPath\$markerValueName" -ForegroundColor Green
    Write-Host "  - Timestamp: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) (Ticks: $currentTicks)" -ForegroundColor Gray
}
catch {
    Write-Warning "Failed to save completion marker. Script may re-run on next execution. Details: $_"
}

# --- Step 8: System Restart ---
Write-Host "`nSecurity hardening script has finished." -ForegroundColor Cyan

Stop-Transcript

if ($NoReboot.IsPresent) {
    Write-Host "The -NoReboot switch was used. System restart has been skipped." -ForegroundColor Yellow
    Write-Host "A restart is still required to apply all changes."
    exit 0
}
else {
    Write-Host "A system restart is required to apply all changes." -ForegroundColor Yellow
    Write-Host "The computer will restart in 30 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    Restart-Computer -Force
}

exit 0
```

## Key Changes from Original

1. **Registry-based run control** - Uses `HKLM:\SOFTWARE\MyLocalChemist\HardeningLastRunTicks` to track last execution
2. **Region-independent date storage** - Uses Ticks (Int64/QWord) instead of string dates to avoid US/UK date format issues
3. **30-day interval** - Script exits gracefully (exit code 0) if run within 30 days
4. **-Force parameter** - Allows bypassing the 30-day check when needed
5. **Step 6.5** - Re-enables location services (registry only, no service manipulation)
6. **Logs to C:\Temp** - Changed from SuperOps folder to avoid cleanup issues
7. **Graceful exit** - Clear messaging when skipping due to recent run

## To Force Re-run

```powershell
# Option 1: Use -Force parameter
.\script.ps1 -Force

# Option 2: Delete registry marker
Remove-ItemProperty -Path "HKLM:\SOFTWARE\MyLocalChemist" -Name "HardeningLastRunTicks"
```

## To Check Last Run Date

```powershell
# Get the ticks value
$ticks = (Get-ItemProperty -Path "HKLM:\SOFTWARE\MyLocalChemist" -Name "HardeningLastRunTicks").HardeningLastRunTicks

# Convert to readable date
[DateTime]::new($ticks)
```
