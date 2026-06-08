# Printer diagnostics

This folder contains incident diagnostics and one-off experiments for the
printer/HSS investigation. These scripts are intentionally outside `includes/`
so the normal customization chain never runs them automatically.

## Production-safe canary scripts

- `Diagnose-MissingPrinter.ps1` inventories queues, drivers, ports, PnP devices,
  and related events.
- `Diagnose-PrinterDriverBlock.ps1` collects policy, driver, Event 808, and
  driver-file evidence for blocked printer plug-ins.
- `Diagnose-PrinterCFGBlock.ps1` inspects Device Guard, WDAC/App Control,
  mitigation state, and PE CFG flags.
- `Diagnose-PrinterBlockTimeline.ps1` correlates BOOT, HSS, and Event 808
  timing.
- `Monitor-HardenSystemSecurityPrinterHealth.ps1` reports HSS rollout state,
  WPP state, printer queue health, and current printer-driver block events for
  SuperOps monitoring.

## Destructive or state-changing experiments

Run these only on a deliberate test endpoint. They may restart the spooler,
change print policy values, create test queues, trigger HSS apply, or restore
queues from PrintBrm backups.

- `Add-BrotherClassDriverProxy.ps1`
- `Test-PrintGuards-*.ps1`
- `Test-ZebraApply-*.ps1`

## Archived drafts

These files are preserved for investigation history only. Do not move them into
`includes/` or run them fleet-wide without a fresh review.

- `archive/epson-tray-queue-draft/` contains the abandoned automatic Epson queue
  and tray-blob restore approach. It can remove Epson queues and the tray restore
  was not reliable enough for production.
- `archive/hss-script-drafts/` contains earlier hardening script drafts kept for
  reference only.

## Handoff notes

- `PRINTER-HSS-ROOT-CAUSE-HANDOFF.md` captures the root-cause reasoning and
  evidence trail for independent review.
