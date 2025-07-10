# Windows Customisation Toolkit

This repository contains a collection of modular PowerShell scripts that remove common bloatware, tighten privacy, install useful applications and apply performance tweaks. The scripts are designed to run after a fresh Windows install so that the system is ready for daily use with minimal manual setup.

[![License: BSD-3](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11%2FServer-blue.svg)](https://www.microsoft.com/windows)

## Safety First

These scripts make extensive changes to the operating system. Before running them:

- **Back up your system or use a virtual machine.**
- **Review the scripts** in the `includes` directory to understand what will change.
- **Test on a non-production machine** whenever possible.
- **Run PowerShell as Administrator** to ensure all steps succeed.

## Getting Started

### 1. Quick install

Open **PowerShell as Administrator** and run the following command. It downloads the repository and launches the main script:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iwr -useb https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1 | iex; \
    & "C:\Temp\customize-windows-setup\customize-windows-setup-main\customize-windows-client.ps1"
```

### 2. Manual install

1. Download `download-repo.ps1` from this repository.
2. Execute the script to extract the repo to `C:\Temp`.
3. Navigate to the extracted folder and run `customize-windows-client.ps1`.

The main script walks through each module in `includes/`, applying changes in alphabetical order. Scripts whose names start with `ZZZ-` run last.

## Features

- **Debloating** – uninstalls many preinstalled apps and disables unwanted services.
- **Privacy hardening** – turns off telemetry, Microsoft advertising and data collection.
- **Security enhancements** – enables BitLocker, strengthens Windows Defender and configures local policies.
- **Application install** – installs common utilities like PowerShell 7, VLC, and other tools via `winget`.
- **System tweaks** – switches to the High Performance power plan, adjusts Explorer and taskbar settings and applies a custom wallpaper.
- **Server support** – includes logic for Windows Server editions with appropriate defaults.

A full list of scripts can be found in the `includes/` folder. Move any script into `includes/disabled/` to skip it during execution.

## Repository Layout

```
customize-windows-setup/
├── customize-windows-client.ps1   # Main orchestrator
├── download-repo.ps1              # Helper to fetch the repo
├── includes/                      # Modular feature scripts
│   └── disabled/                  # Scripts that are not executed
│       └── apply-user-customizations.ps1  # Example HKCU-only script (disabled)
├── wallpaper/                     # Wallpaper assets
└── HKCU-to-HKLM-Migration.md      # Notes about policy changes
```

## Contributing

Contributions are welcome! Please follow the existing script style. The project does not use the Pester framework for testing. If you wish to verify your environment, check the PowerShell version only.

## License

This project is distributed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for details.

