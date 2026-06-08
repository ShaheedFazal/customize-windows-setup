# Handoff: Printer queues removed by security hardening on Windows 11 24H2/25H2

**Purpose:** Independent root-cause investigation. You are a second opinion. The
analysis below reflects one investigator's conclusions — **please challenge them,
not confirm them.** If you see a different root cause, a flaw in the reasoning, or
an untested explanation, say so. Assume nothing here is settled.

---

## 0. The question

On a fleet of Windows 11 **24H2 / 25H2** machines, applying a security-hardening
baseline (HotCakeX "Harden System Security", HSS) **removes essentially every
third-party-driver print queue** on the machine. We want the true root cause and a
**fleet-deployable** fix that keeps meaningful hardening. Two distinct failure
signatures appear (below) and we are not certain they share one cause.

---

## 1. Environment & stack

- **OS:** Windows 11 Pro / IoT Enterprise, builds **26100 (24H2)** and **26200 (25H2)**.
- **Management:** SuperOps RMM. A PowerShell toolkit ("customize-windows-setup")
  runs on each endpoint.
- **Hardening tool:** HotCakeX **Harden System Security (HSS)** — a maximum-grade
  hardening app (WDAC/App Control, exploit protection, ASR, MS Security Baselines,
  spooler hardening, Credential Guard, etc.).
- **Apply mechanism:** the toolkit ships a committed HSS report JSON and applies it
  via a scheduled task running, in an elevated admin desktop session:
  `HardenSystemSecurity.exe --cli ImportReport --in=<report.json> --mode=full`
  - `--mode=full` applies all measures marked "applied" in the report **and
    un-applies** all marked "not applied" (canonical "make machine match report").
  - State is stored at `HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity`
    (`ReportHash`, `LastAppliedStatus`, etc.). A full apply fires when the report
    hash differs or last status != success; otherwise the run is a sub-second no-op.

---

## 2. Symptom — precise

A **full apply** (`ImportReport --mode=full`) removes print queues. Controlled test
on a pristine box (hostname PC19-FA031-5040, build 26200), first-ever full apply,
completed `success` in ~70s:

**Before (6 queues):**
| Queue | Driver | Port |
|---|---|---|
| Brother HL-L5100DN series Printer | Brother HL-L5100DN series | **WSD** |
| Brother HL-L5100DN Drivers | Brother HL-L5100DN series | **WSD** |
| Brother HL-L5200DW Goods in | Brother HL-L5200DW series | **WSD** |
| TOKEN Goodsin | Brother HL-L5200DW series | **WSD** |
| ZDesigner GK420d (Copy 1) | ZDesigner GK420d | **USB002** |
| Microsoft Print to PDF | Microsoft Print To PDF | PORTPROMPT: |

**After:** only **Microsoft Print to PDF** survived. All 5 third-party queues gone.

### Two distinct failure signatures (KEY)

During the apply window, `Microsoft-Windows-PrintService/Admin` **Event 808**
("failed to load a plug-in module") fired only for the **Zebra** and orphaned Epson
modules — **never for the Brothers**:

| Printer | Transport | 808 logged? | Modules / codes |
|---|---|---|---|
| Zebra GK420d | USB | **YES** | `zdnNLM64.dll`, `zdnPMS.dll`, `ZDNui56.dll` — all **0x679** |
| (orphaned Epson, no queue) | n/a | YES | `EFXLM16A.DLL`, `E_YLMBXJE.DLL` — **0x241** |
| All 4 Brothers | WSD | **NO** | none — vanished silently |

- `0x679` = Win32 **1657 / ERROR_DRIVER_BLOCKED** (loader blocked the plug-in).
- `0x241` = Win32 **577 / ERROR_INVALID_IMAGE_HASH** (signature/hash rejection).

So: **USB Zebra = blocked-module-load (logged 808/0x679); WSD Brothers = queue
removed with NO module-load event (silent).** Same trigger, two removal paths.

---

## 3. What the HSS report actually sets (verified by grepping the JSON)

Print/spooler-relevant measures present and applied:
- `RedirectionguardPolicy = 1` (spooler path-redirection guard)
- `CopyFilesPolicy = 1` (CVE-2021-36958 CopyFiles allowlist)
- `…\Printers\PointAndPrint\RestrictDriverInstallationToAdministrators = 1` (CVE-2021-34481)
- `…\Control\Print\RpcAuthnLevelPrivacyEnabled = 1` (CVE-2021-1678)
- `DisableWebPnPDownload` / "Disable HTTP Printing"

**NOT present (grep returned 0 hits):** any `spoolsv` / per-process CFG / exploit-
protection / `MitigationOptions` / `ImageFileExecutionOptions` measure targeting the
spooler. Also: **Windows Protected Print Mode (WPP) is in the report but marked
`NotApplied`**, so `--mode=full` actively turns WPP **off**.

The report also applies broad **App Control / WDAC** — observed separately blocking a
**Zebra driver installer** (it bundles `msiexec.exe` in a temp folder; WDAC refused
`C:\ProgramData\<rand>.tmp\…\msiexec.exe`).

---

## 4. Tests run and results

1. **Full apply (clean box):** breaks printers as in §2. **Reproduces every time.**
2. **Reboots / plain spooler restarts (historical 14-day timeline on another box):**
   **zero** 808s — clean. Only the full-apply window ever produced 808s.
3. **All 4 guards OFF + `Restart-Service spooler`:** **0** new 808; Zebra returned to
   status Normal. (Confound: per #2 a plain restart was going to be clean regardless.)
4. **Single-guard isolation** (enable one guard, others off, restart spooler, repeat
   for all 4): **no guard produced a Zebra 808.** BUT the Zebra canary was already in
   an error state ("Driver is unavailable" from a prior interrupted PrintBrm restore),
   so a non-reattempting queue may not have generated the signal — **inconclusive.**
5. **PrintBrm restore** (`PrintBrm.exe -R -F <export> -O FORCE`) brings queues back,
   but the restored Zebra shows **"Driver is unavailable"** (re-blocked); WSD Brothers
   return. Restore is recovery-only.
6. **HotCakeX GitHub issues:** only one print-related issue (#1160) and it's unrelated
   (Edge `DynamicCodeSettings` crashing Edge print preview). No report of HSS removing
   print queues. Web search corroborates 24H2 breaking legacy print drivers generally
   (independent of HSS).

---

## 5. Current leading hypothesis (CHALLENGE THIS)

The investigator's conclusion (treat as a hypothesis to attack):

> The block is **OS-default Windows 11 24H2 hardened-spooler behaviour**, not a
> removable HSS measure. The report sets no spoolsv CFG mitigation; the spooler's
> per-plug-in CFG/CET/ACG enforcement is a 24H2 platform change. HSS is only the
> **trigger** (its full apply restarts/reconfigures the spooler); the **enforcer** is
> the OS. Corollary: removing the HSS print guards would NOT durably fix it because any
> spooler restart (reboot, Windows Update) re-runs the hardened loader. Proposed fix:
> migrate to Microsoft inbox **class drivers** (network → IPP/PCL6 on a Standard TCP/IP
> port; USB Zebra → Generic/Text-Only + app sends raw ZPL). Hardening stays on.

### Weaknesses in this hypothesis we are aware of
- It does not explain **why a plain reboot/spooler restart is clean** (#2) but the full
  apply is not. If enforcement were purely "any spooler restart on 24H2," reboots
  should also break printers. **Something specific to the full apply triggers it** —
  what? (Driver re-staging? A WDAC/CI policy refresh? A services change? An ASR rule?)
- The **silent** WSD Brother removal (no 808) is unexplained at the mechanism level. We
  grepped the report and found no Function Discovery / WSD / firewall network-discovery
  kill switch. Why do WSD queues disappear with no module-load event?
- The single-guard isolation (#4) was confounded by a broken canary — the guards are
  **not cleanly exonerated.**

---

## 6. Open questions for you

1. **What does `ImportReport --mode=full` do beyond setting these policies + restarting
   the spooler** that a plain reboot does not — and could THAT be the actual queue-
   removal trigger? (Consider: WDAC/CI policy (re)deployment, driver store/blocklist
   refresh, `pnputil`/driver re-eval, service reconfiguration, ASR rules, a spooler
   reset vs restart.)
2. **Mechanism of the silent WSD removal** (no 808). Is it WSD port re-enumeration via
   Function Discovery, `CopyFilesPolicy` invalidating queue-specific files, Redirection
   Guard, or queue deletion by some other apply action?
3. **Is the Zebra 0x679 truly OS-level** (would recur on any 24H2 spooler restart with
   HSS fully removed), or is it tied to a specific applied measure? What is the minimal
   experiment to prove it? (We propose: pristine 24H2 box, NO HSS, install ZDesigner
   driver, `Restart-Service spooler`, check for 808/0x679.)
4. **Is there any single measure (or small set)** whose removal from the report would
   prevent the queue removal while keeping the rest of the baseline? Name it and the
   security cost.
5. **Windows Protected Print Mode** — is enabling it fleet-wide a clean fix for the
   network printers (force Microsoft IPP class driver / green shield), and do Brother
   HL-L5100DN / HL-L5200DW support IPP-Everywhere/Mopria? It is incompatible with the
   USB ZPL Zebra — confirm.
6. **USB Zebra GK420d** — is Generic/Text-Only + raw ZPL the only hardened-safe path,
   or is there a CFG-clean Zebra driver? (Note: the vendor installer is also blocked by
   WDAC, so any fix must be installer-free / inbox.)

---

## 7. Repo files to read (all under the repo root unless noted)

- `includes/Harden-System-Security.report.json` — the ~500KB HSS report (grep, don't
  open whole). The measures in §3 live in `MicrosoftSecurityBaseline.Items`.
- `Ensure-Apps.ps1` — the apply mechanism, the scheduled task, the HKLM state keys, and
  a post-apply override pattern (`Set-RemoteAccessOverride`) that re-asserts a relaxation
  AFTER ImportReport (model any toolkit fix on this).
- `includes/AA-Apply-HardenSystemSecurity.ps1` — runs the apply in the orchestrator.
- `CLAUDE.md` — sections "Harden System Security (HSS) workflow" and "Remote-access
  override" explain the deploy model and constraints.
- Diagnostic scripts already built (root of repo):
  `Test-ZebraApply-1-Baseline.ps1`, `-2-Backup.ps1` (PrintBrm export),
  `-3-TriggerAndWatch.ps1` (force-full apply + live 808 watch + queue diff),
  `-4-Restore.ps1` (PrintBrm restore), `Test-PrintGuards-Remove.ps1`/`-Restore.ps1`,
  `Test-PrintGuards-Isolate.ps1` (slow, PrintBrm between guards),
  `Test-PrintGuards-IsolateFast.ps1` (Zebra-808 canary, no PrintBrm),
  `Add-BrotherClassDriverProxy.ps1` (creates a TCP/IP + inbox class-driver Brother queue
  to test survival).

---

## 8. Constraints & goal

- **Small business** (UK pharmacy, patient data → GDPR/NHS DSPT, but Cyber Essentials /
  DSPT require only the *basics*, NOT HSS-grade hardening). Limited IT time.
- Fix must be **fleet-deployable** via the toolkit (a script/policy/report edit/inbox
  driver pushed by SuperOps) — **NOT** per-machine manual configuration.
- Owner is now considering **removing HSS entirely** and running a proportionate baseline
  (Defender + patching + BitLocker + MFA + backups), optionally a lighter tool
  (HardeningKitty, CIS L1, audit-first). A root cause is still wanted either way.

## 9. What we want from you

1. Your independent **root-cause verdict** — agree, refine, or refute §5, with reasoning.
2. The **single most decisive experiment** to confirm it (cheap, reversible, one box).
3. A **fleet-deployable fix** (or confirmation that removing HSS is the right call for
   this org), with the security trade-off stated plainly.
4. Anything we **missed or got wrong.**

Be blunt. We've spent hours circling; a clear contrary finding is more valuable than
agreement.
