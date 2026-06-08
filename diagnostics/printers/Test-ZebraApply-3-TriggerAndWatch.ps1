<#
.SYNOPSIS
    STEP 3 of the Zebra end-to-end test. THE decisive step. Triggers the real
    HSS full apply (the same scheduled task that breaks other boxes) and watches
    LIVE whether the Zebra queue survives, vanishes, or stays-but-loses its
    print path - capturing the exact 808 modules + error codes.

.DESCRIPTION
    DESTRUCTIVE by design - this is the controlled break.

    SAFETY: refuses to run unless it finds a non-empty PrintBrm backup from
    Step 2 (PrinterBackup-<host>-*.printerExport in C:\Install or C:\Temp).

    Sequence:
      1. Pre-snapshot: printer queues, Zebra queue + status, spooler state,
         and the current 808 high-water (time) so new blocks are unambiguous.
      2. Force-full: clear the stored apply-state key so the trigger is a REAL
         full apply, not a hash-match no-op. After the first apply on a box the
         hash matches + status=success, so without this the task skips the apply
         and the test would falsely report "nothing happened." We delete
         HKLM:\...\HardenSystemSecurity (the wrapper recreates it) to force full.
      2b. Trigger: Start-ScheduledTask on
         \CustomizeWindowsSetup\Apply-HardenSystemSecurityReport - the exact
         mechanism that runs ImportReport --mode=full in an elevated admin
         session.
         NOTE: the apply task needs an interactive ADMIN desktop (HSS.exe needs
         UAC + a desktop). If no admin is logged on, the task won't run and the
         script will tell you to log in as admin and re-run.
      3. Watch loop: polls task state, HKLM LastAppliedStatus, and NEW 808
         events (with module + error code) until the apply reports
         success/failed, plus a grace window for late blocks.
      4. Post-snapshot + DIFF: which queues vanished, is the Zebra still present
         and Normal, and which DLLs got blocked (flag ZDesigner / language
         monitor / port monitor vs cosmetic UI).
      5. Verdict: SURVIVED / VANISHED / PRESENT-BUT-PRINT-PATH-BLOCKED, and asks
         you to physically print a Zebra label to confirm.

    Console + transcript at C:\Temp.

.NOTES
    SuperOps (SYSTEM) with an admin logged on, OR run in an elevated admin
    PowerShell on the box. Self-contained. PS 5.1-safe. No automated tests.
    Part of the Test-ZebraApply-*.ps1 kit (1 baseline, 2 backup,
    3 trigger+watch, 4 restore).
#>

$ErrorActionPreference = 'Continue'

$logDir     = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "ZebraTest-3-Trigger-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block {
    param($InputObject, [string]$Format = 'Table')
    if ($null -eq $InputObject) { Write-Log '  (none)'; return }
    if ($Format -eq 'List') { $text = $InputObject | Format-List * | Out-String -Width 4096 }
    else { $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096 }
    foreach ($line in ($text -split "`r?`n")) { if ($line.TrimEnd()) { Write-Log $line.TrimEnd() } }
}
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$vendorRegex  = 'Epson|Zebra|ZDesigner|ZDN|Brother|BRU|Star|TSP|TM-'
$zebraRegex   = 'Zebra|ZDesigner|ZDN'
$stateKey     = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$taskPath     = '\CustomizeWindowsSetup\'
$taskName     = 'Apply-HardenSystemSecurityReport'
$log808       = 'Microsoft-Windows-PrintService/Admin'

Write-Log "Zebra end-to-end test - STEP 3 TRIGGER + WATCH (destructive)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 0. SAFETY GATE - require a Step 2 backup before breaking anything
# -----------------------------------------------------------------------------
Write-Section '0. Safety gate - confirm Step 2 backup exists'
$backup = $null
foreach ($dir in 'C:\Install','C:\Temp') {
    $cand = Get-ChildItem -LiteralPath $dir -Filter "PrinterBackup-$env:COMPUTERNAME-*.printerExport" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $backup = $cand; break }
}
if (-not $backup) {
    Write-Log "ABORT: no non-empty PrinterBackup-$env:COMPUTERNAME-*.printerExport found in C:\Install or C:\Temp."
    Write-Log "       Run Test-ZebraApply-2-Backup.ps1 first so we have a restore safety net."
    return
}
Write-Log "Backup found : $($backup.FullName)  ($([math]::Round($backup.Length/1KB,1)) KB)"
Write-Log "Safe to proceed - Step 4 can restore from this if needed."

# -----------------------------------------------------------------------------
# 1. PRE-snapshot
# -----------------------------------------------------------------------------
Write-Section '1. PRE-apply snapshot'
function Get-PrinterSnapshot {
    try { return Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus }
    catch { Write-Log "  (Get-Printer failed: $_)"; return @() }
}
$prePrinters = @(Get-PrinterSnapshot)
Write-Log "Printer queues before apply:"
Write-Block $prePrinters 'Table'

$preZebra = @($prePrinters | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
Write-Log ''
Write-Log "Zebra queues before : $($preZebra.Count)"
foreach ($z in $preZebra) { Write-Log "  - $($z.Name)  [$($z.DriverName)]  port=$($z.PortName)  status=$($z.PrinterStatus)" }

$spool = Get-Service -Name Spooler -ErrorAction SilentlyContinue
Write-Log ''
Write-Log "Spooler service     : $($spool.Status)"

# 808 high-water: remember when we started, so any 808 from here on is NEW.
$triggerStart = Get-Date
$pre808Count = 0
try {
    $li = Get-WinEvent -ListLog $log808 -ErrorAction Stop
    if ($li -and $li.IsEnabled) {
        $existing = Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808 } -MaxEvents 200 -ErrorAction SilentlyContinue
        if ($existing) { $pre808Count = $existing.Count }
    }
} catch { }
Write-Log "808 events pre      : $pre808Count (any block after $($triggerStart.ToString('HH:mm:ss')) is NEW)"

# -----------------------------------------------------------------------------
# 2. FORCE FULL - clear stored apply-state so the trigger is a REAL full apply
# -----------------------------------------------------------------------------
Write-Section '2. Force a full apply (clear stored hash/status)'
Write-Log "After the first apply on a box, ReportHash matches + LastAppliedStatus=success,"
Write-Log "so the task would no-op and this test would falsely report 'nothing happened'."
Write-Log "Clearing $stateKey so the next trigger does a genuine full ImportReport."
try {
    $before = Get-ItemProperty -Path $stateKey -ErrorAction SilentlyContinue
    if ($before) {
        Write-Log "  was: ReportHash=$($before.ReportHash)  LastAppliedStatus=$($before.LastAppliedStatus)  LastAppliedUtc=$($before.LastAppliedUtc)"
    } else {
        Write-Log "  (state key already absent - next apply is full anyway)"
    }
    Remove-Item -Path $stateKey -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path $stateKey) {
        Write-Log "  WARNING: could not remove $stateKey - the apply may still no-op. Check perms."
    } else {
        Write-Log "  state cleared - the next apply WILL be full."
    }
} catch { Write-Log "  WARNING clearing state key: $_" }

# -----------------------------------------------------------------------------
# 2b. TRIGGER the real apply task
# -----------------------------------------------------------------------------
Write-Section '2b. Trigger the HSS full apply (Start-ScheduledTask)'
$task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Log "ABORT: scheduled task $taskPath$taskName not found. Has Ensure-Apps run on this box?"
    return
}
Write-Log "Starting task $taskPath$taskName ..."
try {
    Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
    Write-Log "Start-ScheduledTask issued at $((Get-Date).ToString('HH:mm:ss'))."
} catch {
    Write-Log "ERROR starting task: $_"
    return
}

# -----------------------------------------------------------------------------
# 3. WATCH loop - task state, HKLM status, NEW 808s
# -----------------------------------------------------------------------------
Write-Section '3. Watching for apply progress + live 808 blocks'
$maxWaitSec   = 1200   # 20 min ceiling
$pollSec      = 10
$elapsed      = 0
$applyStatus  = $null
$everRunning  = $false
$noMovementWarned = $false
$seen808Ids   = @{}

function Get-New808 {
    param([datetime]$Since)
    $out = @()
    try {
        $evs = Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808; StartTime=$Since } -ErrorAction SilentlyContinue
        foreach ($e in $evs) { $out += $e }
    } catch { }
    return $out
}

while ($elapsed -lt $maxWaitSec) {
    Start-Sleep -Seconds $pollSec
    $elapsed += $pollSec

    $ti = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    $state = if ($ti) { $ti.State } else { 'unknown' }
    if ($state -eq 'Running') { $everRunning = $true }

    try { $applyStatus = (Get-ItemProperty -Path $stateKey -Name 'LastAppliedStatus' -ErrorAction Stop).LastAppliedStatus }
    catch { $applyStatus = $null }

    # surface any new 808s as they land
    $new = Get-New808 -Since $triggerStart
    foreach ($e in $new) {
        if ($seen808Ids.ContainsKey($e.RecordId)) { continue }
        $seen808Ids[$e.RecordId] = $true
        $mm  = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        $cm  = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
        $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
        $code= if ($cm.Success) { $cm.Value } else { '?' }
        $flag= if ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex) { '  <<< ZEBRA' }
               elseif ("$($e.Message)" -match $vendorRegex) { '  <<< vendor' } else { '' }
        Write-Log ("  [{0}] 808 block: {1}  code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code, $flag)
    }

    Write-Log ("  t+{0,4}s  task={1,-8} applyStatus={2,-14} new808={3}" -f $elapsed, $state, "$applyStatus", $seen808Ids.Count)

    if ($applyStatus -eq 'success' -or $applyStatus -eq 'failed') {
        Write-Log "  apply reported '$applyStatus' - entering 30s grace for late 808s..."
        Start-Sleep -Seconds 30
        $new = Get-New808 -Since $triggerStart
        foreach ($e in $new) {
            if ($seen808Ids.ContainsKey($e.RecordId)) { continue }
            $seen808Ids[$e.RecordId] = $true
            $mm  = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
            $cm  = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
            $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
            $code= if ($cm.Success) { $cm.Value } else { '?' }
            Write-Log ("  [{0}] 808 block (grace): {1}  code={2}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code)
        }
        break
    }

    # If nothing is moving after 90s (no Running, no status), the task likely
    # can't run because no admin desktop is available.
    if ($elapsed -ge 90 -and -not $everRunning -and -not $applyStatus -and -not $noMovementWarned) {
        Write-Log ''
        Write-Log "  WARNING: task hasn't entered Running and no apply status after 90s."
        Write-Log "  The apply task needs an interactive ADMIN logon (HSS.exe needs a desktop)."
        Write-Log "  Log in to this box as an admin and re-run Step 3, or run it inside an"
        Write-Log "  elevated admin PowerShell on the box. Continuing to watch a little longer..."
        $noMovementWarned = $true
    }
}

if (-not $applyStatus) {
    Write-Log ''
    Write-Log "No apply status recorded within $maxWaitSec s. Likely the task never ran"
    Write-Log "(no interactive admin). Nothing was broken. Re-run with an admin logged on."
}

# -----------------------------------------------------------------------------
# 4. POST-snapshot + DIFF
# -----------------------------------------------------------------------------
Write-Section '4. POST-apply snapshot + diff'
# spooler may be restarting; retry Get-Printer a few times.
$postPrinters = @()
for ($i=0; $i -lt 6; $i++) {
    $postPrinters = @(Get-PrinterSnapshot)
    if ($postPrinters.Count -gt 0) { break }
    Start-Sleep -Seconds 5
}
Write-Log "Printer queues after apply:"
Write-Block $postPrinters 'Table'

$preNames  = @($prePrinters  | ForEach-Object { $_.Name })
$postNames = @($postPrinters | ForEach-Object { $_.Name })
$vanished  = @($preNames | Where-Object { $_ -notin $postNames })
Write-Log ''
Write-Log "Queues that VANISHED during apply: $($vanished.Count)"
foreach ($v in $vanished) {
    $mark = if ($v -match $zebraRegex) { '  <<< ZEBRA' } elseif ($v -match $vendorRegex) { '  <<< vendor' } else { '' }
    Write-Log "  - $v$mark"
}

$postZebra = @($postPrinters | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
Write-Log ''
Write-Log "Zebra queues after  : $($postZebra.Count) (was $($preZebra.Count))"
foreach ($z in $postZebra) { Write-Log "  - $($z.Name)  status=$($z.PrinterStatus)  port=$($z.PortName)" }

$spool2 = Get-Service -Name Spooler -ErrorAction SilentlyContinue
Write-Log ''
Write-Log "Spooler service after: $($spool2.Status)"

# All NEW 808s, summarised by module.
Write-Section '4b. All NEW 808 blocks from this apply (module + code)'
$allNew = @(Get-New808 -Since $triggerStart | Sort-Object TimeCreated)
if ($allNew.Count -eq 0) {
    Write-Log "  NONE - the apply produced zero plug-in blocks."
} else {
    $zebra808 = $false
    foreach ($e in $allNew) {
        $mm  = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        $cm  = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
        $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
        $code= if ($cm.Success) { $cm.Value } else { '?' }
        $isZ = ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex)
        if ($isZ) { $zebra808 = $true }
        $flag= if ($isZ) { '  <<< ZEBRA' } elseif ("$($e.Message)" -match $vendorRegex) { '  <<< vendor' } else { '' }
        Write-Log ("  {0}  {1,-22} code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code, $flag)
    }
}

# -----------------------------------------------------------------------------
# 5. VERDICT
# -----------------------------------------------------------------------------
Write-Section '5. VERDICT - did the Zebra survive the full apply?'
$zebraVanished = ($preZebra.Count -gt 0 -and $postZebra.Count -lt $preZebra.Count)
$zebraStatusBad = [bool]($postZebra | Where-Object { $_.PrinterStatus -ne 'Normal' })
$zebra808 = [bool](@(Get-New808 -Since $triggerStart) | Where-Object { "$($_.Message)" -match $zebraRegex })

Write-Log "Zebra queues before/after : $($preZebra.Count) -> $($postZebra.Count)"
Write-Log "Zebra queue vanished      : $zebraVanished"
Write-Log "Zebra queue non-Normal    : $zebraStatusBad"
Write-Log "New 808 naming a Zebra DLL : $zebra808"
Write-Log ''
if ($zebraVanished) {
    Write-Log "READ: the Zebra queue DISAPPEARED during the apply. This matches the fleet"
    Write-Log "      experience. The durable fix has to cover the Zebra, not just network MFPs."
} elseif ($zebra808 -or $zebraStatusBad) {
    Write-Log "READ: the Zebra queue SURVIVED as an icon but a Zebra plug-in was BLOCKED (or the"
    Write-Log "      queue is not Normal). It may still LOOK present but fail to PRINT. This is the"
    Write-Log "      'stays-but-broken' mode. >>> PHYSICALLY PRINT A ZEBRA LABEL NOW and report. <<<"
    Write-Log "      The blocked module above tells us whether it's the language monitor (print"
    Write-Log "      path) or just the cosmetic UI plug-in."
} elseif ($postZebra.Count -gt 0) {
    Write-Log "READ: the Zebra queue SURVIVED, Normal, with NO Zebra plug-in block. On THIS box the"
    Write-Log "      full apply did not break it. >>> PHYSICALLY PRINT A ZEBRA LABEL to confirm. <<<"
    Write-Log "      If it prints, USB Zebras survive the apply and your fleet worry is much smaller."
} else {
    Write-Log "READ: inconclusive - no Zebra queue seen after, but none clearly vanished either."
    Write-Log "      Check the post snapshot above and the apply status."
}

Write-Section 'Step 3 complete'
Write-Log "Transcript: $transcript"
Write-Log "Now PRINT A ZEBRA LABEL physically and tell me the result."
Write-Log "If anything is wrong, Step 4 (restore) brings printers + trays back from:"
Write-Log "  $($backup.FullName)"
