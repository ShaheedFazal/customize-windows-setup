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
- **Old:** `HKCU:\Software\Microsoft\Clipboard\EnableCloudClipboard = 0`
- **New:** HKLM policies under `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`
  setting `AllowClipboardHistory = 1` and `AllowCrossDeviceClipboard = 0`.
- **Impact:** clipboard history remains available while cross device sync is disabled for all users.
- **Rollback:** delete or adjust the HKLM policy values.
