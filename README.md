# Customize Windows Client

This repository contains a collection of PowerShell scripts that streamline the setup of a Windows installation. The main script `customize-windows-client.ps1` orchestrates a set of modular actions found in the `includes` directory to disable unwanted features, tweak system defaults and install common tools.

The project started as a fork of [filipnet/customize-windows-client](https://github.com/filipnet/customize-windows-client) and retains the BSD 3-Clause license. Many customization ideas were inspired by the [windows-trimify](https://github.com/toolarium/windows-trimify) project.

## Requirements
- PowerShell 5.1 or newer
- Run the script with administrative privileges

## Usage
1. Download or clone this repository. You can also run `download-repo.ps1` to automatically fetch and extract it.
   To retrieve and invoke the script in one line, run (it saves the repository to your **Downloads** folder by default):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1 | iex"
   ```
2. Adjust variables near the top of `customize-windows-client.ps1` to suit your environment.
3. Review the scripts in the `includes` folder. Delete or move any file to `includes/disabled` to skip that action.
4. If using `Disable-MicrosoftAccount.ps1`, ensure a local administrator account exists and that you can sign in with it. This module blocks Microsoft account sign-in. To revert later, run:
   ```powershell
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 0 /f
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 0 /f
   reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 1 /f
   ```
5. Launch the script:
   ```powershell
   .\customize-windows-client.ps1
   ```
   If the execution policy is restricted, start it with:
   ```powershell
   powershell -ExecutionPolicy Bypass .\customize-windows-client.ps1
   ```

Each script in `includes` performs a single customization step—such as disabling Cortana, blocking Microsoft account sign-in and Windows Hello for Business, configuring Windows Update, or installing useful tools. `Set-WallpaperWithStats.ps1` can also set a wallpaper and overlay basic system information.

## Contributing
Contributions are welcome! New customization modules or improvements to existing scripts help keep this project useful for different environments.

## Credits
- **Benedikt Filip** ([@filipnet](https://github.com/filipnet)) created the original project that formed the basis of this repository.
- Several ideas and snippets were adopted from [toolarium/windows-trimify](https://github.com/toolarium/windows-trimify) – see its [license](https://github.com/toolarium/windows-trimify/blob/master/LICENSE).

## License
This repository and all scripts are distributed under the BSD 3-Clause license. See [LICENSE](LICENSE) for the full text.

