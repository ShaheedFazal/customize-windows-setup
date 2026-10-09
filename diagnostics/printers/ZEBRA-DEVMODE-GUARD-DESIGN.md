# Design: guard Zebra label settings against Event 318 resets

Status: **design + detection only.** Nothing in this branch changes printers,
the HSS report, or the apply task. The restore guard (section 4.3) is specified
here but not built. It depends on checks V1 to V6 in section 5 passing on a real
box first.

## 1. Incident (2026-09-15, PC2-FQ688-4074)

Win11 25H2 (26200). USB Zebra ZD421-203dpi ZPL, ZDesigner v10.6.26.28275, queue
`ZDesigner ZD421-203dpi ZPL` on USB001. Titan PMR prints through Crystal Reports
as Windows user `MyLocalChemist`.

| Time | Event |
|---|---|
| 2026-09-14 | Branch staff swapped the printer (new serial D8J252303386) |
| 09:31 | `\CustomizeWindowsSetup\Apply-HardenSystemSecurityReport` ran, result 0x0 |
| 09:33 | PrintService/Admin **318**: "Failed to upgrade printer settings ... Error: 1801 ... set to those configured by the manufacturer" |
| 09:39 | First Titan job printed with the driver default 4x6in size, so LABEL LENGTH was 1225 dots instead of ^LL610. The printer went media-out, the job hung and blocked 10 more. The queue still showed Normal because there is no language monitor or bidi. |

Fix on the day: cleared the queue. Set Printing Defaults **and** MyLocalChemist's
Printing Preferences to 104 x 76.2 mm, labels with gaps, direct thermal, tear
off. Then calibrated.

## 2. Is the HSS apply really the cause? Not proven

### What Event 318 is

Microsoft documents 318 as `MSG_DRIVER_FAILED_UPGRADE`, under **Printer Driver
Installation Status**. The spooler logs it when it tries to carry a queue's
saved settings (DEVMODE) across a driver upgrade or re-initialisation and the
driver's upgrade call fails. It then falls back to the manufacturer defaults.
Microsoft's only fix is to set the Printing Defaults again. Error 1801 is
`ERROR_INVALID_PRINTER_NAME`. The same 318/1801 pair is reported with HP
Universal Print Driver on print servers, so it is not specific to Zebra.

So the direct trigger is the spooler's **driver-upgrade path**. Several things
can reach that path: a driver being added or re-added, a new device instance
getting its driver installed, a spooler start with a pending driver change, or
possibly the HSS apply reconfiguring the spooler.

### Why the incident does not yet prove HSS did it

1. **Result 0x0 does not show that ImportReport ran.** The apply payload in
   [Ensure-Apps.ps1](../../Ensure-Apps.ps1) exits 0 on *both* paths:
   - the full apply
   - the hash-match no-op, which logs "Hash matches ... skip ImportReport" and
     never touches the spooler

   Only `C:\Temp\Apply-HardenSystemSecurityReport.log` and `LastAppliedUtc` tell
   them apart.
2. **The report has not changed since 2026-06-08** (commit d08f7e4), and the
   payload not since 2026-06-05. A box that already applied the June report
   successfully would hash-match on 2026-09-15 and do nothing. A full apply at
   09:31 would only happen if PC2's `LastAppliedStatus` was not `success`, or its
   stored hash was missing.
3. **09:31 fits the logon trigger**, which has a 5-minute delay. That puts a user
   logon at about 09:26 and quite possibly a boot. A boot starts the spooler, and
   the printer was swapped the day before. A new USB serial means a new device
   instance and a driver install for it, which is exactly the 318 code path.
4. The earlier fleet timeline showed plain reboots produce no **808**, but nobody
   looked for **318**. Those are different code paths.

### How to settle it

- **On PC2 now (read-only):** run
  [Diagnose-PrinterBlockTimeline.ps1](Diagnose-PrinterBlockTimeline.ps1), which
  this branch extends. For every 318 it lists what happened in the 15 minutes
  before: boot, `HSS-FULL` vs `HSS-NOOP`, spooler start/stop, driver install
  (PrintService 316, UserPnp 20001/20003), and Zebra USB arrival (Kernel-PnP
  400/410 for VID_0A5F). Each gets a verdict. Also read `LastAppliedUtc`: a
  2026-09-15 value means a full apply, a June value means a no-op.
- **Decisive experiment (test box, reversible):** set a Zebra queue to 104 x 76.2,
  save a baseline with `Inspect-ZebraPrinterSettings.ps1 -SaveBaseline`, then run
  these one at a time. After each, run the inspector and check for 318:
  1. `Restart-Service Spooler`
  2. reboot
  3. forced full apply (`Test-ZebraApply-3-TriggerAndWatch.ps1`)
  4. re-add the same driver (`Add-PrinterDriver -Name "ZDesigner ZD421-203dpi ZPL"`)
  5. unplug and replug on a different USB port

  Whichever of these produces a 318 is a trigger. It may well be more than one.

**Design consequence:** all of these triggers leave the queue in the same
state. The guard must not depend on which one fired.

## 3. Why a restore inside the apply payload alone would not have prevented this

The repo rule (CLAUDE.md, `Set-RemoteAccessOverride`) is that post-apply logic
goes in the apply payload, because an `includes/` script would race the
asynchronous apply. The same problem applies one level down: **the spooler's
upgrade pass is itself asynchronous to the payload.**

- In the incident, 318 came about 2 minutes after the task started. A full
  apply takes about 70 s. A restore placed after ImportReport would have run at
  about 09:32, *before* the 09:33 reset, and been overwritten.
- If 09:31 was a no-op, the restore on the hash-match path would have run at
  09:31. Also too early.
- Resets from a boot, driver install or printer swap never reach the payload.

The payload can still *trigger* a check. But the thing that fixes a 318 has to
run **after** the 318. That means an event-triggered task.

## 4. Mechanism

### 4.1 Layer 0: detection and alert (in this branch)

[Monitor-HardenSystemSecurityPrinterHealth.ps1](Monitor-HardenSystemSecurityPrinterHealth.ps1)
now emits:

| SuperOps field | Meaning |
|---|---|
| `ZebraSettings_Status` | `DEFAULT_SIZE` (alert): the Printing Defaults, or a signed-in user's Printing Preferences, decode as 4x6in. `RESET_RECENT`: a Zebra 318 in the last 24 h, but sizes are no longer the default. `OK`, `NO_ZEBRA`, `UNKNOWN`. |
| `ZebraSettings_Last318` | latest Zebra 318 |
| `ZebraSettings_NearHss` | a Zebra 318 within 15 min of `LastAppliedUtc`. That value is only written by a full apply. |
| `ZebraSettings_Detail` | e.g. `ZDesigner ZD421-203dpi ZPL: defaults=104x76.2,MyLocalChemist=104x76.2` |

Status is driven by the settings **as they are now**, not by the event.
A 318 is one-shot. Settings at the driver default are the actual fault.

Create the four fields in SuperOps (RMM Monitoring class) and alert on
`ZebraSettings_Status = DEFAULT_SIZE`. On Zebra boxes, run the monitor every
15 to 30 min. The incident gave 6 minutes between reset and first job, so an
alert alone will not always beat the next label. That is why layer 2 exists.

"Driver default = 4x6in" is a heuristic. It is confirmed only for the ZD421 in
this incident, so check other Zebra models' defaults before relying on it.
The baseline comparison in layer 2 is the exact check.

### 4.2 Layer 1: known-good baseline (in this branch)

A technician runs
[Inspect-ZebraPrinterSettings.ps1](Inspect-ZebraPrinterSettings.ps1) `-SaveBaseline`
**after a correct label has printed from Titan**. It never auto-captures: an
automatic capture on a box that has already been reset would store the broken
settings as known-good. It refuses to save 4x6 unless `-AllowDriverDefaultSize`
is passed. It writes to
`C:\ProgramData\CustomizeWindowsSetup\PrinterSettings\<queue>\`:

- `global-gd.dat`: `rundll32 printui.dll,PrintUIEntry /Ss /n "<queue>" /a <file> /q g d`
- `user-<SID>-DevModePerUser.bin` / `-DevModes2.bin`: raw per-user blobs
- `baseline.json`: driver name and version, port, decoded sizes, hashes

The folder is ACL'd to SYSTEM and Administrators. A SYSTEM restore feeds these
blobs to the driver inside spoolsv, so a user-writable blob would be an attack
surface.

**printui flags, checked against the PrintUIEntry reference:**
`/Ss` stores, `/Sr` restores. Flags go at the end:
- `2` PRINTER_INFO_2
- `7` PRINTER_INFO_7
- `c` colour profile
- `d` printer data
- `s` security descriptor
- `g` global DEVMODE
- `m` minimal settings
- `u` user DEVMODE
- `r` resolve name conflicts
- `f` force name
- `p` resolve port

Choices here:

- **`g d` only.** `2` also restores the port and driver name. After a printer
  swap that can point the queue at a dead port. `s` restores the security
  descriptor, which the hardened baseline owns.
- **Never `u`.** It acts on the *calling* user's HKCU. As SYSTEM or a tech admin
  it captures and restores the wrong user, not MyLocalChemist.
- **Always `/q`.** Without it, a failure opens a modal dialog, which would hang a
  hidden SYSTEM task.
- **Quote the queue name inside one argument string.** `Start-Process`
  joins `-ArgumentList` with spaces without quoting, and ZDesigner queue names
  contain spaces.
- **Never trust the exit code.** rundll32's exit code means nothing. The Epson
  canary in this repo (`Repair-EpsonWfC579rQueues.ps1 -ApplySavedSettings`)
  saw `/Sr d g u` report success without changing anything. Every restore must
  be verified by reading the settings back.

### 4.3 Layer 2: restore guard (specified, not built)

**Task:** `\CustomizeWindowsSetup\Guard-ZebraPrinterSettings`, registered by a
new `Register-ZebraSettingsGuardTask` in [Ensure-Apps.ps1](../../Ensure-Apps.ps1).
Payload: `C:\ProgramData\CustomizeWindowsSetup\Guard-ZebraPrinterSettings.task.ps1`.
Principal: **SYSTEM**, which needs no admin session. `MultipleInstances IgnoreNew`.

Triggers:

| Trigger | Why |
|---|---|
| Event: `Microsoft-Windows-PrintService/Admin`, EventID 318, delay PT1M | fires **after** any reset, whatever caused it (the race in section 3) |
| At startup, delay PT5M | catches a reset logged before the task could fire |
| At logon (any user) | per-user preferences can only be fixed once that user's hive is loaded |
| Daily | drift sweep |
| `Start-ScheduledTask` from the apply payload, after ImportReport **and** on the hash-match path | meets the "after apply" requirement without running printer code in the admin-user payload |

Event trigger registration (PS 5.1 has no `-OnEvent` switch):

```powershell
$cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskEventTrigger
$t318 = New-CimInstance -CimClass $cls -ClientOnly
$t318.Enabled = $true
$t318.Delay = 'PT1M'
$t318.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-PrintService/Admin"><Select Path="Microsoft-Windows-PrintService/Admin">*[System[(EventID=318)]]</Select></Query></QueryList>'
```

Per queue that has a `baseline.json`:

1. Queue missing: log `queue-missing` and stop. Recreating queues is
   `Ensure-ZebraUsbQueues.ps1`'s job.
2. Driver name or version differs from the baseline: record `driver-changed`
   and **do not restore**. A DEVMODE blob belongs to one driver version, and
   feeding an old one to a new driver is exactly what fails in 318. Alert and
   re-baseline by hand.
3. Settle: wait until the spooler has been running at least 60 s and no 318 has
   arrived in the last 60 s. Give up after 5 min and record `unsettled`.
4. **Printing Defaults:** decode `Default DevMode`. If it matches the baseline
   size, record `ok`. Otherwise:
   - back up the current blob
   - run `printui /Sr /n "<queue>" /a global-gd.dat /q g d`
   - re-read it: `restored` if it now matches, else `restore-failed` (alert)
5. **Per-user preferences:** for each *loaded* hive that has a baseline file,
   check `HKU\<SID>\Printers\DevModePerUser\<queue>`. If it is the driver default
   or differs from the baseline size:
   - back up the current value
   - write the baseline blob with `Set-ItemProperty -Type Binary`
   - re-read and record the result

   Users with no baseline are reported only. Signed-out users are deferred to
   the logon trigger.
6. **Stuck jobs:** if jobs submitted before the fix are still queued, record
   `jobs-pending-after-reset` and alert. The printer may already be media-out
   and need a cancel and calibration. The guard **never deletes jobs**.
7. **Rate limit:** at most 3 restores per queue per 24 h. After that, record
   `restore-loop`, alert, and stop restoring.

State goes to `HKLM:\SOFTWARE\CustomizeWindowsSetup\ZebraSettingsGuard\<queue>`:
`LastCheckUtc`, `LastResult`, `LastResetEventUtc`, `LastRestoreUtc`,
`RestoreCount24h`. The monitor adds a `ZebraSettings_Guard` field from it.

**Hard limits.** The guard does not:
- touch the HSS report, policies or the spooler service
- create or delete queues
- use flags other than `g d`
- restore across driver versions
- write outside the baseline folder, the guard state key and the per-user
  `DevModePerUser` value

### 4.4 Why per-user is by registry and not `printui u`

Titan prints as MyLocalChemist. That user's `HKCU\Printers\DevModePerUser\<queue>`
overrides the queue defaults for their jobs. When that value is absent, the user
inherits the Printing Defaults.

`printui ... u` only reads and writes the caller's own HKCU. Using it would need
a per-user task running as MyLocalChemist, and the baseline would have to be
captured as that user too. A SYSTEM process can read and write the loaded hive
directly, which is simpler.

Whether winspool picks up a directly written value without restarting Titan is
**unverified** (V5).

## 5. Checks that must pass before layer 2 is built

| # | Check | How |
|---|---|---|
| V1 | ZDesigner keeps the label size in the public DEVMODE fields, so the decoder reads 104 x 76.2 on PC2 | `Inspect-ZebraPrinterSettings.ps1` on PC2 (known good now). If it shows 101.6 x 152.4 or nonsense, the size lives in driver-private data. In that case switch detection to the PrintTicket `PageMediaSize` line the same script prints. |
| V2 | MyLocalChemist's preferences live in `DevModePerUser` (vs `DevModes2`) | same run, with MyLocalChemist signed in |
| V3 | `printui /Ss g d` works under the hardened baseline (not blocked by App Control) | `-SaveBaseline` on PC2 writes `global-gd.dat` |
| V4 | `printui /Sr g d` **actually changes** ZDesigner settings | test box: set defaults to 4x6 by hand, `/Sr`, re-read, print a label |
| V5 | a direct per-user registry write is honoured | test box: write the blob, open Printing Preferences as that user, print from Titan (with and without restarting Titan) |
| V6 | the 318 event trigger fires under the baseline | reproduce a 318 with whichever step in section 2 produced one, and confirm the task ran |

If V4 fails, the fallback is detection plus alert only (layer 0). The per-user
part (V5) can still work on its own.

## 6. Alternatives rejected

- **PrintBrm restore:** recreates queues. The restored Zebra came back "Driver is
  unavailable" (handoff section 4.5). Too heavy for a settings drift.
- **`Set-PrintConfiguration -PaperSize`:** standard sizes only. There is no
  104 x 76.2 and no Zebra-private fields (media type, darkness, tear-off).
  Useful for detection only.
- **Raw ZPL `^LL610` to the printer:** the driver resends its own setup with
  every job, and raw jobs sent while the printer is red never leave the spooler.
- **Generic / Text Only driver:** Titan's Crystal labels rely on the ZDesigner
  driver. Out of scope.
- **Dropping an HSS measure:** out of bounds, and not shown to be the cause.

## 7. Rollout

1. Merge this branch. It is diagnostics only, with no fleet behaviour change.
   Create the four SuperOps fields and the `DEFAULT_SIZE` alert.
2. On PC2: run the timeline to settle section 2, then run the inspector to cover
   V1 and V2. With a good label confirmed, run `-SaveBaseline` (V3).
3. On a test Zebra box: V4 to V6, plus the trigger experiment in section 2.
4. Build layer 2 in `Ensure-Apps.ps1`. Canary on PC2, then all Zebra branches.
   Baselines are captured per branch, because stock differs by branch.
