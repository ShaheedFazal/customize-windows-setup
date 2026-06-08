# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Windows Customization Toolkit - A collection of PowerShell scripts for automating Windows post-installation customization, debloating, privacy hardening, and system optimization. Transforms fresh Windows installations into streamlined, privacy-focused systems.

**Target Environment**: Windows 10/11/Server (2016+)
**Language**: PowerShell 5.1+
**License**: BSD 3-Clause
**Testing**: No automated testing framework (intentional - see AGENTS.md)

## Core Architecture

### Execution Model

The main orchestrator [customize-windows-client.ps1](customize-windows-client.ps1) follows this pattern:

1. **Administrator Check**: Auto-elevates if not running as admin
2. **Initialization**: Creates system restore point, sets up logging to `C:\Temp\`
3. **Registry Backup**: Backs up HKLM, HKCR, HKU hives to `C:\Install\`
4. **Script Discovery**: Loads all `.ps1` files from [includes/](includes/) (excluding [includes/disabled/](includes/disabled/))
5. **Sequential Execution**: Runs scripts alphabetically; `ZZ-` prefixed scripts run last, `ZZZ-` run final
6. **Multi-User Application**: Applies changes to current user, all loaded profiles, and default template
7. **Error Handling**: Non-blocking errors with comprehensive logging

### Registry Policy Architecture

**Critical Pattern**: This toolkit uses **HKLM (Local Machine)** policies instead of **HKCU (Current User)** settings to ensure system-wide application and resistance to user-level changes.

- See [HKCU-to-HKLM-Migration.md](HKCU-to-HKLM-Migration.md) for migration rationale
- All new scripts MUST use HKLM policies where available
- Use `Set-RegistryValue` from [Shared-Functions.ps1](includes/Shared-Functions.ps1) for consistency

### Shared Functions System

**ALWAYS use** [includes/Shared-Functions.ps1](includes/Shared-Functions.ps1) for registry operations:

```powershell
# Load shared functions (already done in main script)
. (Join-Path $IncludesPath 'Shared-Functions.ps1')

# Registry operations
Set-RegistryValue -Path "HKLM:\SOFTWARE\..." -Name "ValueName" -Value 1 -Type "DWord" -Force
Remove-RegistryValue -Path "HKLM:\SOFTWARE\..." -Name "ValueName"
Remove-RegistryKey -Path "HKLM:\SOFTWARE\..."

# Logging
Write-Log "Operation completed successfully"
```

### Multi-User Application Pattern

Scripts apply changes to:
1. **Current User**: `HKCU:\` for immediate effect
2. **All Loaded Profiles**: `HKU:\<SID>\` for existing users
3. **Default Template**: `HKU:\.DEFAULT\` for new user accounts
4. **System-Wide Policies**: `HKLM:\SOFTWARE\Policies\` for enforcement

See [includes/Enable-NumLock.ps1](includes/Enable-NumLock.ps1:76-80) for reference implementation.

## Key Configuration Variables

Located at top of [customize-windows-client.ps1](customize-windows-client.ps1:28-40):

```powershell
$DRIVELABELSYS = "OS"                      # System drive label
$TEMPFOLDER = "C:\Temp"                    # Logging and temp files
$INSTALLFOLDER = "C:\Install"              # Registry backups
$POWERMANAGEMENT = "High performance"      # Power plan name
$OFFICESUITE = "Google"                    # Default: "Google" or "LibreOffice"
$WINDOWSBUILD = (Get-WmiObject Win32_OperatingSystem).BuildNumber
```

## Script Naming Conventions

- **Regular scripts**: `Verb-Feature.ps1` (e.g., `Disable-Cortana.ps1`)
- **ZZ- prefix**: Execute after regular scripts (e.g., `ZZ-Disable-MicrosoftAccount.ps1`)
- **ZZZ- prefix**: Execute last, for finalization (e.g., `ZZZ-Set-Wallpaper.ps1`)
- **Disabled scripts**: Move to [includes/disabled/](includes/disabled/) to exclude from execution

## Common Development Patterns

### Creating New Customization Scripts

1. Create `.ps1` file in [includes/](includes/)
2. Use shared functions for registry operations
3. Implement try-catch with non-blocking errors
4. Write to shared log via `Write-Log`
5. Test on VM before committing

Example template:
```powershell
# Description of what this script does

Write-Host "[INFO] Configuring feature..." -ForegroundColor Cyan

try {
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\..." `
                      -Name "SettingName" `
                      -Value 1 `
                      -Type "DWord" `
                      -Force

    Write-Log "Feature configured successfully"
    Write-Host "[SUCCESS] Feature configured" -ForegroundColor Green
} catch {
    Write-Log "ERROR: Failed to configure feature - $_"
    Write-Host "[ERROR] Configuration failed: $_" -ForegroundColor Red
}
```

### Enabling/Disabling Features

- **Disable**: Move script from [includes/](includes/) → [includes/disabled/](includes/disabled/)
- **Enable**: Move script from [includes/disabled/](includes/disabled/) → [includes/](includes/)
- **Warning**: Scripts in `disabled/` may be outdated, conflicting, or enterprise-specific

### Wake on LAN Pattern

[includes/Enable-WakeOnLan.ps1](includes/Enable-WakeOnLan.ps1) demonstrates international language support:
- Uses universal adapter detection (not English-only keywords)
- Filters by `HardwareInterface` property, not adapter names
- Tries multiple property name variations for WoL settings
- Handles language-independent registry names

### Consolidated Screen Lock Approach

**Important**: Screen lock is integrated into [includes/Set-PowerManagement-HighPerformance.ps1](includes/Set-PowerManagement-HighPerformance.ps1) rather than using separate screensaver scripts.

Pattern:
```powershell
# Set 15-minute display timeout
powercfg /setacvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 900
powercfg /setdcvalueindex $currentGuid SUB_VIDEO VIDEOIDLE 900

# Configure lock screen timeout
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
                  -Name "InactivityTimeoutSecs" -Value 900 -Type "DWord" -Force

# Set screensaver policies for additional security
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
                  -Name "ScreenSaveActive" -Value "1" -Type "String" -Force
```

## Testing Guidelines

**From [AGENTS.md](AGENTS.md):**
- **No Pester framework** - intentional design decision
- **No automated test suite** - do not add one
- **Manual testing only** - test on VMs with multiple Windows versions
- **PowerShell version check only** - verify compatibility if needed

## Git Workflow

- Create feature branches for all work
- Commit messages should follow existing style (imperative mood)
- Recent commit pattern examples:
  - "Prioritize numeric values for Wake on LAN configuration"
  - "Enhance Wake on LAN script with international language support"
  - "Implement universal Wake on LAN adapter detection"

## Common Pitfalls

1. **Don't use HKCU for new features** - Use HKLM policies for system-wide enforcement
2. **Don't skip shared functions** - Always use `Set-RegistryValue`, not direct `Set-ItemProperty`
3. **Don't create blocking errors** - Use try-catch with logging, allow script continuation
4. **Don't add Pester tests** - See AGENTS.md
5. **Don't assume English** - Network adapter names, registry display names vary by locale
6. **Don't create conflicting scripts** - Check [includes/disabled/](includes/disabled/) for similar functionality

## Key Files Reference

- [customize-windows-client.ps1](customize-windows-client.ps1) - Main orchestrator
- [includes/Shared-Functions.ps1](includes/Shared-Functions.ps1) - Shared utilities (registry, logging, `Test-MachineWideSentinel`)
- [download-repo.ps1](download-repo.ps1) - Repository downloader for one-line installation
- [Ensure-Apps.ps1](Ensure-Apps.ps1) - SuperOps SYSTEM bootstrap: installs PS7/Chrome/Drive machine-scope; registers per-user logon+daily task for HSS (Microsoft Store app, must install in user context)
- [Verify-Apps.ps1](Verify-Apps.ps1) - SuperOps drift detector for the apps Ensure-Apps installs
- [includes/A0-Backup-PrintersBeforeHSS.ps1](includes/A0-Backup-PrintersBeforeHSS.ps1) - Creates a local PrintBrm printer backup before the HSS apply task is triggered.
- [includes/AA-Apply-HardenSystemSecurity.ps1](includes/AA-Apply-HardenSystemSecurity.ps1) - Stages the HSS report into `C:\ProgramData\CustomizeWindowsSetup` and triggers the elevated scheduled task that runs HSS in an admin user session.
- [includes/Harden-System-Security.report.json](includes/Harden-System-Security.report.json) - The hardening config that AA-Apply imports
- [HKCU-to-HKLM-Migration.md](HKCU-to-HKLM-Migration.md) - Registry policy migration documentation
- [AGENTS.md](AGENTS.md) - Testing framework guidance

## Harden System Security (HSS) workflow

This repo deploys a HotCakeX Harden System Security report by staging it from [includes/Harden-System-Security.report.json](includes/Harden-System-Security.report.json) into `C:\ProgramData\CustomizeWindowsSetup\Harden-System-Security.report.json`, then triggering `\CustomizeWindowsSetup\Apply-HardenSystemSecurityReport`. The scheduled task is registered by [Ensure-Apps.ps1](Ensure-Apps.ps1) and runs in an elevated admin user session because the packaged HSS app cannot run correctly under SYSTEM/session 0.

Before staging the report, [includes/A0-Backup-PrintersBeforeHSS.ps1](includes/A0-Backup-PrintersBeforeHSS.ps1) creates a local PrintBrm backup under `C:\Install\PrinterBackups`. This is a manual recovery safety net only; the rollout does not automatically restore printers.

### Updating the report

When the user provides a new JSON (typically as a file path, often somewhere under their Google Drive), do this:

1. Read the path the user gave you and copy/overwrite `includes/Harden-System-Security.report.json` with that content.
2. **Do not rewrite, prettify, or modify the JSON.** It's a verbatim export from the HSS app — treat it as opaque content.
3. The file is large (~500 KB). If `Read` errors with "exceeds maximum allowed size," that's expected — just copy it with `cp` via Bash; you don't need to read it to commit it.
4. Commit with a message like `Update HSS hardening report (from <yyyy-mm-dd export>)`.
5. Open PR, squash-merge.

### How it deploys

- The next customize run on each endpoint stages the report and triggers `\CustomizeWindowsSetup\Apply-HardenSystemSecurityReport`.
- The scheduled task computes the SHA-256 of the staged report, compares it with `HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity\ReportHash`, and only calls `HardenSystemSecurity.exe --cli ImportReport --in=<staged-report> --mode=full` when the hash differs or the last apply was not successful.
- `--mode=full` applies all measures marked "applied" in the report AND removes all measures marked "not applied" — it's the canonical "make this machine match the report" command per the HSS wiki.
- Subsequent customize runs with the same report are no-ops inside the scheduled task (hash matches).

### Prerequisite: HSS must be installed on the endpoint

HSS is a Microsoft Store app and can't be installed under SYSTEM (winget msstore is unreliable there). [Ensure-Apps.ps1](Ensure-Apps.ps1) handles this by registering a scheduled task that runs at user logon and installs HSS in the user's context.

Verify install state on an endpoint with `Get-AppxPackage -AllUsers VioletHansen.HardenSystemSecurity`. If empty, the user-logon task hasn't fired yet — see [Ensure-Apps.ps1](Ensure-Apps.ps1) for the bootstrap path.

### Remote-access override (scoped to named hosts only)

The MS Security Baseline in the report sets `SeDenyNetworkLogonRight = *S-1-5-113` ("Deny access to this computer from the network" for all **local** accounts). With NLA on, RDP does a Type 3 network logon during pre-auth, so local-account RDP fails with `0x1307` / `STATUS_LOGON_TYPE_NOT_GRANTED` — and Windows OpenSSH (also a network logon) would fail identically. HSS ships no override for this specific right.

`Set-RemoteAccessOverride` in the apply-task payload ([Ensure-Apps.ps1](Ensure-Apps.ps1)) re-opens access **after** `ImportReport` (so it always wins over the freshly-applied baseline) and on the hash-match no-op path (so steady-state machines keep it). It is **scoped to the `$sshHosts` list** (currently just `GFC-SERVER-01`):

- **Listed hosts:** enable RDP (`fDenyTSConnections=0`) and relax `SeDenyNetworkLogonRight` to Guests-only via `secedit`, enabling OpenSSH and RDP-with-NLA. **NLA stays on.**
- **Every other endpoint:** the function returns immediately — left completely untouched and fully hardened (no RDP change, no NLA change). This is deliberate: local-account RDP requires dropping either NLA or the network-logon deny, so the relaxation is confined to the one box that needs SSH. Add a hostname to `$sshHosts` to extend it to another box.

Do **not** move this logic into a customize `includes/` script — the HSS apply runs asynchronously in a scheduled task, so an include would race it and get clobbered when the baseline re-applies.

## Per-run sentinel pattern for machine-wide includes

The orchestrator iterates every include once per loaded user hive (typically 3×: current user, default template, signed-in user). Includes that only write to HKLM or otherwise machine-wide state should guard with `Test-MachineWideSentinel` from [includes/Shared-Functions.ps1](includes/Shared-Functions.ps1):

```powershell
if (Test-MachineWideSentinel -Name 'My-Script') { return }
# ... rest of the script
```

The helper drops `C:\Temp\<name>.session` on first call and returns `$true` on subsequent calls. [customize-windows-client.ps1](customize-windows-client.ps1) sweeps `C:\Temp\*.session` at startup so every customize run begins fresh.

**Don't sentinel scripts that write to `HKCU:` or iterate per-user state** — the orchestrator remaps `HKCU:` to a different hive per iteration, so those legitimately need to run multiple times.

## Windows Server Considerations

- Scripts auto-detect Server editions via `$WINDOWSBUILD`
- Server-specific logic uses comparisons: `$WINDOWSBUILD -ge $WINDOWSSERVER2016`
- Exclude client-only features (e.g., Windows Store apps) on Server editions
