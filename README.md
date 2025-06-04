# Customize Windows Client

This repository contains a collection of PowerShell scripts that streamline the setup of a Windows installation. The main script `customize-windows-client.ps1` orchestrates a set of modular actions found in the `includes` directory to disable unwanted features, tweak system defaults and install common tools.

The project started as a fork of [filipnet/customize-windows-client](https://github.com/filipnet/customize-windows-client) and retains the BSD 3-Clause license. Many customization ideas were inspired by the [windows-trimify](https://github.com/toolarium/windows-trimify) project.

## Requirements
- PowerShell 5.1 or newer
- Run the script with administrative privileges

## Usage
1. **Open PowerShell as Administrator.** The script needs elevated privileges to modify system settings.
2. **Allow script execution for this session.** Temporarily bypass the execution policy:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```

3. **Download this repository.** Clone it manually or run `download-repo.ps1`, which fetches and extracts the archive for you. To retrieve and run the helper in one step (files go to your **Downloads** folder), run:

   ```powershell
   $d = Join-Path $env:USERPROFILE 'Downloads'; iwr -Uri 'https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1' -OutFile (Join-Path $d 'download-repo.ps1'); & "$d\download-repo.ps1"
   ```

   To download the repository **and** start `customize-windows-client.ps1` immediately, run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; iwr -useb https://raw.githubusercontent.com/ShaheedFazal/customize-windows-setup/main/download-repo.ps1 | iex; & `"$env:USERPROFILE\Downloads\customize-windows-setup\customize-windows-setup-main\customize-windows-client.ps1`""
   ```

   **Caution:** Review the code before running the one line command.

4. Adjust variables near the top of `customize-windows-client.ps1` to suit your environment.
5. Review the scripts in the `includes` folder. Delete or move any file to `includes/disabled` to skip that action.
6. If using `Disable-MicrosoftAccount.ps1`, ensure a local administrator account exists and that you can sign in with it. This module blocks Microsoft account sign-in. To revert later, run:
   ```powershell
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 0 /f
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v BlockUserFromCreatingAccounts /t REG_DWORD /d 0 /f
   reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 1 /f
   ```
7. **Run the script from the same console** so you can respond to prompts:

   ```powershell
   .\customize-windows-client.ps1
   ```

   If the execution policy is still restricted, start it with:

   ```powershell
   powershell -ExecutionPolicy Bypass .\customize-windows-client.ps1
   ```

   The script asks for confirmation before customizing Windows and again before rebooting. Press `y` and **Enter** when prompted.

Each script in `includes` performs a single customization step—such as disabling Cortana, blocking Microsoft account sign-in and Windows Hello for Business, configuring Windows Update, or installing useful tools. `Configure-StartPins.ps1` resets pinned items to File Explorer, Google Chrome, Telegram and WhatsApp Web. `Set-WallpaperWithStats.ps1` can set a wallpaper and overlay basic system information.

## Troubleshooting

### App removal errors

Running `Uninstall-Default-Software-Packages.ps1` may produce messages like:

```
Remove-AppxPackage : Deployment failed with HRESULT: 0x80073CFA, Removal failed.
Remove-AppxProvisionedPackage : The system cannot find the path specified.
```

The script checks whether each package is installed before attempting removal.
If a package was partially removed or corrupted you may still see these
messages. They generally mean the app is already gone and can be ignored.

## Contributing
Contributions are welcome! New customization modules or improvements to existing scripts help keep this project useful for different environments.

## Credits
- **Benedikt Filip** ([@filipnet](https://github.com/filipnet)) created the original project that formed the basis of this repository.
- Several ideas and snippets were adopted from [toolarium/windows-trimify](https://github.com/toolarium/windows-trimify) – see its [license](https://github.com/toolarium/windows-trimify/blob/master/LICENSE).

## License
This repository and all scripts are distributed under the BSD 3-Clause license. See [LICENSE](LICENSE) for the full text.

