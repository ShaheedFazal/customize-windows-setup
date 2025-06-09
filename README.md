# Windows Customisation Toolkit

A comprehensive PowerShell toolkit for post-installation Windows setup that removes bloatware, strengthens privacy, installs essential applications, and optimises system configuration for productivity and security.

[![License: BSD-3](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue.svg)](https://www.microsoft.com/windows)

## ⚠️ Important Safety Notice

**This toolkit makes significant system modifications.** Before proceeding:

- ✅ **Create a full system backup** or VM snapshot
- ✅ **Ensure you have a local administrator account** (particularly important if using a Microsoft account)
- ✅ **Review the scripts** in the `includes` folder to understand what will be changed
- ✅ **Test on a non-production system first**

The toolkit can optionally create a system restore point and registry backup, but these are not substitutes for proper backups.

## 🚀 Quick Start

### Option 1: One-Line Installation (Recommended)

Open **PowerShell as Administrator** and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; iwr -useb https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1 | iex; & `"$env:USERPROFILE\Downloads\customize-windows-setup\customize-windows-setup-main\customize-windows-client.ps1`""
```

### Option 2: Manual Installation

1. **Open PowerShell as Administrator**
2. **Allow script execution:**
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```
3. **Download the repository:**
   ```powershell
   $d = Join-Path $env:USERPROFILE 'Downloads'; iwr -Uri 'https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1' -OutFile (Join-Path $d 'download-repo.ps1'); & "$d\download-repo.ps1"
   ```
4. **Navigate to the downloaded folder and run:**
   ```powershell
   cd "$env:USERPROFILE\Downloads\customize-windows-setup\customize-windows-setup-main"
   .\customize-windows-client.ps1
   ```

## 🎯 What This Toolkit Does

### 🛡️ Privacy & Security Enhancements
- **Disables telemetry and data collection** across Windows components
- **Removes advertising ID** and content suggestions
- **Blocks Microsoft account sign-in prompts** (with safety checks)
- **Enables BitLocker encryption** with automatic key backup
- **Configures Windows Defender** with optimal settings
- **Enables SmartScreen (App & Browser Control)** for safer downloads
- **Enables UAC** and sets appropriate security policies
- **Disables unnecessary services** that could pose security risks

### 🧹 System Debloating
- **Removes pre-installed bloatware** including games, promotional apps, and unwanted Microsoft apps
- **Uninstalls OneDrive** (optional) with complete cleanup
- **Disables Cortana** and Bing search integration
- **Removes Xbox features** and Game DVR functionality
- **Cleans up default Start Menu** pins and shortcuts

### ⚙️ System Optimisation
- **Installs essential applications** via Windows Package Manager (winget)
- **Adds desktop shortcuts** for installed apps by scanning all Start Menu folders
- **Configures Windows Update** with intelligent scheduling and deferral
- **Sets up automatic app updates** via scheduled task
- **Optimises power management** settings
- **Enables Wake-on-LAN** for compatible hardware
- **Configures clipboard** settings for productivity

### 🎨 Interface Improvements
- **Customises taskbar** appearance and removes unnecessary icons
- **Sets file associations** for common document types
- **Applies custom wallpaper** with system information overlay
- **Configures Control Panel** for easier navigation
- **Shows file extensions** and optimises Explorer settings

## 📦 Included Applications

The toolkit automatically installs these essential applications:

**Core Runtimes:**
- .NET Desktop Runtime (6, 7, 8)
- Microsoft Visual C++ Redistributables

**Productivity Tools:**
- Google Chrome + Google Drive
- LibreOffice (full office suite)
- Notepad++ (advanced text editor)

**System Utilities:**
- 7-Zip (file archiver)
- VLC Media Player
- Windows Terminal
- PowerShell 7

**Communication:**
- Microsoft Teams
- Telegram Desktop
- Zoom

**Development:**
- Python 3
- Remote desktop tools (AnyDesk)

All applications are kept up-to-date via a weekly scheduled task.

## 🔧 Customisation Options

### Adding/Removing Features

To **disable** any feature:
1. Move the corresponding script from `includes/` to `includes/disabled/`
2. The main script will skip any files in the `disabled` folder

To **add custom scripts:**
1. Create a new `.ps1` file in the `includes/` folder
2. Use the naming convention: `Verb-Feature.ps1`
3. For scripts that must run last, use the `ZZ-` prefix

### Configuring Variables

Edit the top of `customize-windows-client.ps1` to customise:

```powershell
$DRIVELABELSYS = "OS"                    # System drive label
$TEMPFOLDER = "C:\Temp"                  # Temporary files location
$POWERMANAGEMENT = "High performance"     # Power plan preference
```

### Office Suite Selection

The toolkit prompts you to choose between:
- **Google Workspace** (web-based, requires Chrome)
- **LibreOffice** (offline, full-featured)

File associations and shortcuts are configured automatically based on your choice.

## 🔒 Security Features

### BitLocker Configuration
- Automatically enables BitLocker on the system drive
- Uses TPM-only protection for seamless boot experience
- Saves recovery key to `Documents/BitLockerRecoveryKey-COMPUTERNAME.txt`
- **Important:** Back up this file to a secure location

### Microsoft Account Handling
- Detects existing Microsoft accounts and warns about potential lockout
- Offers to create local administrator account as backup
- Provides clear instructions for reverting changes if needed

### System Hardening
- Configures account lockout policies (5 attempts, 30-minute lockout)
- Sets password policies (8 character minimum, unlimited age)
- Enables Windows Firewall across all profiles
- Allows ICMP (ping) through firewall for network diagnostics

## 📊 Advanced Features

### Custom Wallpaper with System Info
Places a custom wallpaper with overlaid system information:
- Computer name and workgroup
- Hardware model and serial number
- Windows version

To use: Place your image as `wallpaper/wallpaper.png` in the toolkit directory.

### Scheduled Maintenance
- **Daily shutdown check:** Automatically shuts down inactive systems after 9 PM
- **Weekly app updates:** Updates all winget-managed applications every Sunday at 8 AM or on next boot if missed
- **Smart shutdown logic:** Only triggers when no users are actively logged in

### Network Configuration
- Enables Wake-on-LAN for compatible Ethernet adapters
- Disables WiFi Sense and hotspot auto-connect
- Configures Windows Update delivery optimisation

## 🔍 Troubleshooting

### Common Issues and Solutions

**App removal errors (HRESULT: 0x80073CFA):**
- These indicate apps are already removed and can be safely ignored

**"Script execution is disabled" error:**
- Run: `Set-ExecutionPolicy Bypass -Scope Process -Force`

**Winget not found:**
- The toolkit automatically installs winget if missing
- Requires internet connection during first run

**File association changes don't apply:**
- Ensure `SetUserFTA.zip` was downloaded and extracted successfully
- Check that target applications are properly installed

**Microsoft account lockout:**
- Create a local admin account before running the toolkit
- See README section on reverting Microsoft account blocks

### Reverting Microsoft Account Changes

If you're locked out after disabling Microsoft account features:

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 1 /f
```

### Log Files

All operations are logged to:
- `C:\Temp\customize-windows-client-YYYYMMDD-HHMMSS.log`

Check this file for detailed information about any errors or warnings.

## 🏗️ Development & Contributing

### Project Structure
```
customize-windows-setup/
├── customize-windows-client.ps1      # Main orchestrator
├── download-repo.ps1                 # Repository fetcher
├── includes/                         # Modular customisation scripts
│   ├── disabled/                     # Scripts to skip
│   └── *.ps1                        # Individual feature scripts
├── wallpaper/                        # Custom wallpaper directory
└── README.md                         # This file
```

### Contributing Guidelines
- Each script handles a single responsibility
- Test on multiple Windows editions (Home, Pro, Enterprise)
- Follow existing error handling patterns
- Update documentation for new features
- No breaking changes to the main orchestrator

### Code Standards
```powershell
# Registry modification pattern
If (!(Test-Path "HKLM:\Path\To\Key")) {
    New-Item -Path "HKLM:\Path\To\Key" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\Path\To\Key" -Name "ValueName" -Type DWord -Value 0

# Error handling
Get-Service "ServiceName" -ErrorAction SilentlyContinue
```

## 📋 System Requirements

- **Windows 10/11** (Home, Pro, Enterprise, or Server editions)
- **PowerShell 5.1 or newer**
- **Administrator privileges** required
- **Internet connection** for downloading applications
- **4GB+ free space** recommended for application installations

## 📄 License & Credits

This project is licensed under the **BSD 3-Clause License** - see the [LICENSE](LICENSE) file for details.

### Credits
- **Original project:** [filipnet/customize-windows-client](https://github.com/filipnet/customize-windows-client) by Benedikt Filip
- **Additional inspiration:** [toolarium/windows-trimify](https://github.com/toolarium/windows-trimify)

---

**⭐ If this toolkit helped you, please consider starring the repository!**
