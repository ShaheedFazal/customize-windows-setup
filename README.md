# Windows Customisation Toolkit

A comprehensive PowerShell-based toolkit for post-installation Windows setup that removes bloatware, strengthens privacy and security, installs essential applications, and optimises system configuration for maximum productivity.

[![License: BSD-3](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11%2FServer-blue.svg)](https://www.microsoft.com/windows)

## ⚠️ Critical Safety Information

**This toolkit performs extensive system modifications.** Before proceeding:

- ✅ **Create a complete system backup** or VM snapshot
- ✅ **Ensure you have a local administrator account** (essential if currently using Microsoft account)
- ✅ **Review all scripts** in the `includes` folder to understand changes
- ✅ **Test on a non-production system first**
- ✅ **Close all running applications** before execution

The toolkit includes automatic restore point creation and registry backup, but these are **not substitutes for proper system backups**.

## 🚀 Quick Start Guide

### Method 1: One-Command Installation

Open **PowerShell as Administrator** and execute:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; iwr -useb https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1 | iex; & `"$env:USERPROFILE\Downloads\customize-windows-setup\customize-windows-setup-main\customize-windows-client.ps1`""
```

### Method 2: Manual Installation

1. **Open PowerShell as Administrator**
2. **Set execution policy:**
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```
3. **Download repository:**
   ```powershell
   $downloadPath = Join-Path $env:USERPROFILE 'Downloads'
   iwr -Uri 'https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1' -OutFile (Join-Path $downloadPath 'download-repo.ps1')
   & "$downloadPath\download-repo.ps1"
   ```
4. **Execute the toolkit:**
   ```powershell
   cd "$env:USERPROFILE\Downloads\customize-windows-setup\customize-windows-setup-main"
   .\customize-windows-client.ps1
   ```
   The script runs **interactively** and will pause for user input at several steps.
   If it appears to stop, look for a prompt at the bottom of the PowerShell window.

## 🎯 Comprehensive Feature Overview

### 🛡️ Privacy & Security Hardening

**Telemetry & Data Collection Removal:**
- Disables Windows telemetry at the most restrictive level (Security/Enterprise only)
- Removes advertising ID and targeted content suggestions
- Disables diagnostic tracking service and related scheduled tasks
- Blocks feedback collection and user experience improvement programmes

**Microsoft Account & Authentication:**
- Intelligently blocks Microsoft account sign-in prompts with safety checks
- Disables Windows Hello for Business (with local account verification)
- Prevents Microsoft 365 promotional notifications
- Offers guided local account creation for safety

### 🛡️ Privacy & Security Enhancements
- **Disables telemetry and data collection** across Windows components
- **Removes advertising ID** and content suggestions
- **Blocks Microsoft account sign-in prompts** (with safety checks)
- **Enables BitLocker encryption** with automatic key backup
- **Configures Windows Defender** with optimal settings
- **Enables SmartScreen (App & Browser Control)** for safer downloads
- **Enables UAC** and sets appropriate security policies
- **Disables unnecessary services** that could pose security risks

### 🧹 Advanced System Debloating

**Microsoft App Removal:**
- Removes 40+ pre-installed Microsoft apps including Solitaire, Xbox, Office Hub, 3D Builder
- Cleans up Bing-integrated apps (News, Weather, Sports, Finance)
- Removes Windows Media Player and legacy components
- Uninstalls messaging, camera, and social apps

**Third-Party Bloatware:**
- Removes 25+ sponsored applications (Candy Crush, Netflix, Spotify trials, etc.)
- Cleans Disney, gaming, and promotional apps
- Removes social media and entertainment trial software
- Eliminates developer tool trials and promotional content

**Microsoft Edge Debloating:**
- Disables 18+ Edge features including telemetry, shopping assistant, collections
- Removes Microsoft Rewards integration and promotional content
- Disables crypto wallet and donation features
- Blocks enhanced images and personalisation reporting

**OneDrive Management:**
- Complete OneDrive uninstallation with registry cleanup
- Removes OneDrive from File Explorer integration
- Cleans up leftover folders and shortcuts
- Alternative: OneDrive disable-only option available

### ⚙️ System Optimisation & Performance

**Essential Software Installation (via winget):**
- **.NET Runtimes:** Desktop Runtime 6, 7, 8 + Visual C++ Redistributables
- **Productivity:** LibreOffice suite, Notepad++, 7-Zip, VLC Media Player
- **Communication:** Microsoft Teams (per-user or machine-wide installs handled), Telegram Desktop, Zoom
- **Development:** PowerShell 7, Python 3, Windows Terminal
- **Google Workspace:** Chrome browser, Google Drive desktop client
- **Remote Access:** AnyDesk for technical support

**Windows Update Intelligence:**
- Automatic download with scheduled installation
- Prevents auto-reboot while users are logged on
- Defers feature updates for 180 days, quality updates for 7 days
- Sets active hours (8 AM - 7 PM) with reboot suppression
- Enables driver updates and recommended updates
- Disables delivery optimisation to prevent bandwidth sharing

**Power & Performance:**
- Disables hibernation to reclaim disk space and prevent hybrid sleep issues
- Disables Fast Startup for proper Wake-on-LAN functionality
- Enables Wake-on-LAN on compatible Ethernet adapters
- Configures smart auto-shutdown for inactive systems after 9 PM

### 🎨 Interface & User Experience

**Taskbar & Start Menu Optimisation:**
- Hides search box, Task View, People, and Widgets icons
- Disables Windows 11 Widgets feature
- Shows small taskbar icons for space efficiency
- Displays all system tray icons for better visibility
- Removes recently and frequently used items from Explorer

**File Explorer Enhancements:**
- Shows known file extensions (optional, in disabled folder)
- Hides user folder shortcut from desktop
- Removes Pictures, Videos, Music, and 3D Objects from This PC view
- Sets Control Panel to small icons (classic view)

**Custom Wallpaper System:**
- Applies a custom wallpaper
- Supports custom images via `wallpaper/wallpaper.png`
- Utilises BGInfo when `wallpaper/WallpaperSettings` is found. The script downloads BGInfo automatically if needed.
- Configures a startup entry so the wallpaper is re-applied at each logon

**Office Suite Integration:**
- Interactive choice between Google Workspace (web-based) and LibreOffice
- Automatic file association configuration for documents, spreadsheets, presentations
- Google Workspace option includes desktop shortcuts and file associations
- LibreOffice option provides full offline productivity suite

### 🔧 Network & Connectivity

**Network Security:**
- Disables WiFi Sense hotspot sharing and auto-connect features
- Enables Remote Desktop with Network Level Authentication
- Configures Windows Firewall with ICMP ping allowance
- Disables WAP Push Service for mobile carrier integration

**Remote Access:**
- Enables Remote Desktop with secure authentication
- Disables Remote Assistance to prevent unauthorised access
- Configures Wake-on-LAN for remote power management
- Sets up AnyDesk for professional remote support

### 🔒 Advanced Security Features

**BitLocker Implementation:**
- Automatic TPM-based encryption for seamless boot experience
- Recovery password generation and secure storage
- Used-space-only encryption for faster initial setup
- Hardware test skipped automatically when adding a new TPM protector to avoid user prompts
- Recovery key backup to `Documents/BitLockerRecoveryKey-COMPUTERNAME.txt`

**Windows Server Specific:**
- Disables IE Enhanced Security Configuration (ESC) for administrators
- Configures Automatic Virtual Machine Activation (AVMA) keys
- Disables Windows Admin Center popup in Server Manager
- Server 2016/2019 specific optimisations

**System Hardening:**
- Disables guest account and removes administrator description
- Configures account lockout and password policies
- Sets machine inactivity timeout (15 minutes)
- Enables clipboard history while disabling cross-device sync

## 📦 Application Management

### Automated Installation & Updates

The toolkit installs essential applications and sets up automated maintenance:

**Weekly Update Schedule:**
- Creates scheduled task running every Sunday at 8 AM
- Updates all winget-managed applications automatically
- Runs as SYSTEM account for reliable execution
- Generates update script at `C:\Scripts\Update-WingetApps.ps1`

- **File Association Management:**
- Downloads and configures SetUserFTA.exe for reliable file associations.
- Falls back to a built-in registry method and finally the `assoc` command when SetUserFTA is unavailable.
- Supports both Chrome-based (Google Workspace) and LibreOffice associations
- Handles PDF, Office documents, and web protocols
- Maintains consistency across user profiles
- Integrates methods from [PS-SFTA](https://github.com/DanysysTeam/PS-SFTA) so
  existing accounts receive updated associations immediately

### Smart Features

**Intelligent Shutdown System:**
- Monitors for active user sessions after 9 PM
- Only shuts down when no users are actively logged in
- Provides 60-second warning before shutdown
- Checks every 15 minutes for 6 hours (9 PM - 3 AM)

## 🔧 Customisation & Configuration

### Feature Toggle System

**Enable/Disable Features:**
- Move scripts between `includes/` and `includes/disabled/` folders
- Scripts in `disabled/` folder are completely skipped
- No code modification required for feature toggling

**Execution Order Control:**
- Scripts execute alphabetically
- Use `ZZ-` prefix for scripts requiring dependencies (e.g., `ZZ-Enable-BitLocker.ps1`)
- Dependency-aware execution ensures proper setup sequence

### Configuration Variables

Modify variables in `customize-windows-client.ps1`:

```powershell
$DRIVELABELSYS = "OS"                      # System drive label
$TEMPFOLDER = "C:\Temp"                    # Logging and temporary files
$INSTALLFOLDER = "C:\Install"              # Installation files and backups
$POWERMANAGEMENT = "High performance"       # Preferred power plan
$DRIVELETTERCDROM = "z:"                   # CD-ROM drive letter assignment
```

### Advanced Customisation Options

**Wallpaper Personalisation:**
1. Add your image as `wallpaper/wallpaper.png`.
2. (Optional) place a `WallpaperSettings` file created by BGInfo in the same folder.
3. Run `ZZZ-Set-Wallpaper.ps1` to apply the wallpaper. The script downloads BGInfo if missing and uses the settings file to generate the wallpaper.
4. The script sets up a startup task so the wallpaper reloads automatically at logon.

**Microsoft Edge Policies:**
- 18 configurable policies in `Debloat-MicrosoftEdge.ps1`
- Granular control over telemetry, features, and integrations
- Enterprise-grade configuration options

## 🔍 Troubleshooting & Support

### Common Issues & Solutions

**App Removal Errors (HRESULT: 0x80073CFA):**
- Indicates apps already removed or partially uninstalled
- Generally harmless and can be safely ignored
- Script includes error handling for these scenarios

**Script Execution Policy Restrictions:**
```powershell
# Temporary bypass for current session
Set-ExecutionPolicy Bypass -Scope Process -Force

# Or run with bypass flag
powershell -ExecutionPolicy Bypass .\customize-windows-client.ps1
```

**Winget Installation Failures:**
- Toolkit automatically installs winget if missing
- Requires internet connection for Microsoft Store App Installer
- Falls back gracefully if automatic installation fails

**Microsoft Account Lockout Prevention:**
- Toolkit detects existing Microsoft accounts
- Prompts for local account creation before proceeding
- Warns about potential lockout scenarios

-**File Association Issues:**
- Ensure `SetUserFTA.exe` downloaded successfully to `C:\Scripts\`. The toolkit falls back to a registry method and then `assoc` if needed
- Verify target applications installed correctly
- Run file association scripts after application installation
- **Parsing Errors After Manual Extraction:**
  - Some third-party unzip tools can corrupt PowerShell files
  - Re-download using the provided `download-repo.ps1` script or `Expand-Archive`
  - Confirm `Profile-Template-Functions.ps1` contains around 430 lines
  - If issues persist, clone the repo using `git clone` to avoid line-ending corruption

### Recovery Procedures

**Restore Microsoft Account Access:**
```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\PassportForWork" /v Enabled /t REG_DWORD /d 1 /f
```

**System Restore Options:**
- **System Restore Point:** Created automatically before modifications
- **Registry Backups:** Saved to `C:\Install\registry-backup-*.reg`
- **Log Files:** Complete execution log at `C:\Temp\customize-windows-client-*.log`

### Diagnostic Information

**Log Analysis:**
- All console output captured with timestamps
- Error codes and warnings preserved for troubleshooting
- Successful operations confirmed with [OK] status messages

**Windows Edition Compatibility:**
- Automatic detection of Windows build numbers
- Server-specific features handled appropriately
- Graceful degradation for missing features

## 🏗️ Development & Architecture

### Project Structure

```
customize-windows-setup/
├── customize-windows-client.ps1           # Main orchestrator script
├── download-repo.ps1                      # Repository download utility
├── Create-Standard-User.ps1               # Standalone user creation
├── includes/                              # Modular feature scripts
│   ├── Configure-*.ps1                    # System configuration
│   ├── Disable-*.ps1                      # Feature disabling
│   ├── Enable-*.ps1                       # Feature enabling
│   ├── Hide-*.ps1                         # UI element hiding
│   ├── Install-*.ps1                      # Software installation
│   ├── Set-*.ps1                          # Setting configuration
│   ├── Strengthen-Privacy.ps1             # Privacy hardening
│   ├── Uninstall-*.ps1                    # Software removal
│   ├── ZZ-*.ps1                          # Dependencies (run last)
│   └── disabled/                          # Disabled features
├── wallpaper/                             # Custom wallpaper assets
│   └── README.md                          # Wallpaper instructions
├── AGENTS.md                              # AI assistant guidelines
└── README.md                              # This documentation
```

### Contributing Guidelines

**Code Standards:**
```powershell
# Registry modification pattern with safety checks
If (!(Test-Path "HKLM:\Path\To\Key")) {
    New-Item -Path "HKLM:\Path\To\Key" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\Path\To\Key" -Name "ValueName" -Type DWord -Value 0

# Service management with error handling
Stop-Service "ServiceName" -WarningAction SilentlyContinue
Set-Service "ServiceName" -StartupType Disabled

# App removal with validation
function Uninstall-PackageIfPresent {
    param([string]$Identifier)
    $package = Get-AppxPackage $Identifier -ErrorAction SilentlyContinue
    if ($null -ne $package) {
        $package | Remove-AppxPackage -ErrorAction SilentlyContinue
    }
}
```

**Development Requirements:**
- Test across Windows editions (Home, Pro, Enterprise, Server)
- Maintain backwards compatibility where possible
- Follow single-responsibility principle for scripts
- Include comprehensive error handling
- Document security implications of changes

### Architecture Principles

**Modular Design:**
- Each script handles one specific customisation area
- Alphabetical execution with dependency control via naming
- Easy feature toggling via file system organisation

**Safety First:**
- Automatic backups before major changes
- Extensive validation and warning systems
- Graceful degradation for unsupported features

**Enterprise Ready:**
- Server edition compatibility
- Domain environment considerations
- Scalable deployment patterns

## 📋 System Requirements

**Supported Platforms:**
- Windows 10 (1909 or later) - Home, Pro, Enterprise, Education
- Windows 11 (all editions)
- Windows Server 2016/2019/2022

**Prerequisites:**
- **PowerShell 5.1** or newer (Windows PowerShell or PowerShell 7)
- **Administrator privileges** (UAC elevation required)
- **Internet connection** for application downloads and winget functionality
- **4GB+ available storage** for application installations
- **TPM 1.2/2.0** recommended for BitLocker functionality

**Hardware Compatibility:**
- **Ethernet adapter** for Wake-on-LAN features
- **Compatible graphics** for wallpaper features
- **Standard x64 architecture** (ARM64 support limited)

## 📄 Legal & Licensing

### License

This project is distributed under the **BSD 3-Clause License**. See [LICENSE](LICENSE) for complete terms.

### Credits & Attribution

**Original Foundation:**
- [filipnet/customize-windows-client](https://github.com/filipnet/customize-windows-client) by Benedikt Filip
- Core architecture and initial script collection

**Additional Inspiration:**
- [toolarium/windows-trimify](https://github.com/toolarium/windows-trimify) - Various customisation techniques
- Community contributions and feedback

**Current Development:**
- [ShaheedFazal](https://github.com/ShaheedFazal) - Enhanced features and maintenance

### Disclaimer

This toolkit modifies system settings and removes software. Use at your own risk. The developers are not responsible for any system issues, data loss, or conflicts that may arise. Always backup your system before use.

---

## 🌟 Recognition

If this toolkit has improved your Windows experience, please consider:
- ⭐ **Starring the repository** to show support
- 🔄 **Sharing with others** who might benefit
- 🐛 **Reporting issues** to help improve the project
- 💡 **Contributing ideas** for new features

**Your feedback drives continuous improvement!**
