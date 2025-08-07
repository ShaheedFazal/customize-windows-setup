# HKCU to HKLM Policy Migration

This document summarizes the system-wide policy changes introduced in Phase 2.
Each section lists the original per-user registry values that were replaced and
the corresponding HKLM policy keys that provide the same behaviour for all
accounts.

## Strengthen-Privacy.ps1
- **Old:** `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled = 0`
- **Old:** `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\* = 0`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy = 1`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableWindowsConsumerFeatures = 1`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableCloudOptimizedContent = 1`
- **Safe because:** these policies are documented in Microsoft's group policy templates and apply to all users.
- **Impact:** advertising ID and consumer content features are disabled for every user account.
- **Rollback:** delete the created registry values or set them back to `0`.

## Disable-Cortana.ps1
- **Old:** HKCU input personalization values under `\Microsoft\InputPersonalization`
- **New:** HKLM policies under `HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization` controlling
  `AllowInputPersonalization`, `RestrictImplicitTextCollection` and `RestrictImplicitInkCollection`.
- **Safe because:** the policy keys are part of Windows administrative templates.
- **Impact:** Cortana and related input personalization features are disabled for all users.
- **Rollback:** remove the HKLM values or set them to their defaults.

## Disable-Bing-Search.ps1
- **Old:** HKCU search preferences `BingSearchEnabled` and `CortanaConsent`.
- **New:** HKLM policies in `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` including
  `DisableWebSearch`, `AllowCortana`, and `ConnectedSearchUseWeb`.
- **Impact:** prevents Bing web results in the Windows search box system-wide.
- **Rollback:** delete or change the HKLM policy values.

## Disable-Feedback.ps1
- **Old:** HKCU feedback suppression via `NumberOfSIUFInPeriod`.
- **New:** HKLM policies `DoNotShowFeedbackNotifications` and `AllowTelemetry` under the
  Windows data collection keys.
- **Impact:** hides feedback prompts and sets telemetry level 0 for everyone.
- **Rollback:** remove the registry values to restore default behaviour.

## Configure-Clipboard.ps1
- **Old:** `HKCU:\Software\Microsoft\Clipboard\EnableClipboardHistory = 1`
- **New:** HKLM policies under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`
  setting `AllowClipboardHistory = 1` and `AllowCrossDeviceClipboard = 0`.
- **Impact:** clipboard history remains available while cross device sync is disabled for all users.
- **Rollback:** delete or adjust the HKLM policy values.

## Disable-Action-Center.ps1
- **Old:** `HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer\DisableNotificationCenter = 1`
- **Old:** `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications\ToastEnabled = 0`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\DisableNotificationCenter = 1`
- **New:** `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications\ToastEnabled = 0`
- **Impact:** turns off Action Center and toast notifications for every user.
- **Rollback:** remove these HKLM values or set them back to their defaults.

## Hide-Search-Icon-Taskbar.ps1
- **Old:** `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search\SearchboxTaskbarMode = 0`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\SearchBoxTaskbarMode = 0`
- **Impact:** ensures the taskbar search box stays hidden system-wide.
- **Rollback:** delete the HKLM policy value or set it to `1` or `2` to restore the search icon or box.

## Disable-Autorun.ps1
- **Old:** `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun = 255`
- **New:** `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun = 255`
- **Impact:** disables Autorun for all drives across every user account.
- **Rollback:** re-create the HKCU value or adjust the HKLM setting to re-enable Autorun.

## Hide-User-Folder-From-Desktop.ps1
- **Old:** Deleted `{59031a47-3f72-44a7-89c5-5595fe6b30ee}` under `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu`
- **Old:** Deleted `{59031a47-3f72-44a7-89c5-5595fe6b30ee}` under `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\HideDesktopIcons\ClassicStartMenu\{59031a47-3f72-44a7-89c5-5595fe6b30ee} = 1`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\HideDesktopIcons\NewStartPanel\{59031a47-3f72-44a7-89c5-5595fe6b30ee} = 1`
- **Impact:** hides the User Folder icon on the desktop for all users.
- **Rollback:** remove the HKLM values or set them to `0` to show the icon again.

## Enable-NumLock.ps1
- **Old:** `HKCU:\Control Panel\Keyboard\InitialKeyboardIndicators = 2` and `HKEY_USERS\.DEFAULT\Control Panel\Keyboard\InitialKeyboardIndicators = 2`
- **New:** `HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\Keyboard\InitialKeyboardIndicators = 2` when the administrative template is present. Otherwise, the value is set across all loaded user hives.
- **Safe because:** the policy key is part of Windows administrative templates and enforces consistent behaviour.
- **Impact:** Num Lock starts enabled for every user account without per-user overrides once policy enforcement is available.
- **Rollback:** remove the HKLM policy value and reset individual user hive settings as needed.
