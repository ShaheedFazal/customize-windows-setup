<#
.SYNOPSIS
    Read-only TIMELINE correlation for ONE printer box: do Event 808 plug-in
    blocks and Event 318 printer-settings resets line up with HSS FULL apply
    runs, with boots, with spooler restarts, or with driver/device installs?
    This is the test that separates "HSS triggers it" from "it's the Windows
    print engine / a driver install doing it".

.DESCRIPTION
    Builds a single merged chronological timeline over the last N days of:
      [BOOT]     - system start (Event Log 6005 / Kernel-General 12)
      [HSS-FULL] - HSS apply task actually ran ImportReport (apply log
                   "Applying via" / "Apply succeeded" / "Apply failed", plus
                   HKLM LastAppliedUtc)
      [HSS-NOOP] - HSS apply task fired but the hash matched, so ImportReport
                   was SKIPPED. A no-op run does not touch the spooler, so it
                   cannot be the cause of anything. Scheduled-task result 0x0
                   does NOT distinguish these two - only the apply log does.
      [HSS-RUN]  - apply task fired / was triggered (neutral marker)
      [SPOOL]    - Print Spooler service entered running/stopped state
                   (System 7036, matched on the service name in the binary
                   data, so it is locale-independent)
      [DRV]      - printer driver added/updated (PrintService/Admin 316) or a
                   PnP driver install for a printer/Zebra device (UserPnp
                   20001/20003)
      [USB]      - a Zebra (VID_0A5F) or USBPRINT device was configured
                   (Kernel-PnP/Configuration 400/410): printer swap, replug,
                   first-seen serial
      [808]      - spooler plug-in-block bursts (PrintService/Admin 808),
                   collapsed into ~10-minute buckets with a count
      [318]      - "Failed to upgrade printer settings ... set to those
                   configured by the manufacturer" (PrintService/Admin 318).
                   This is the DEVMODE reset: the queue's Printing Defaults
                   fall back to the driver default (4x6in for ZDesigner).

    READ THE TIMELINE:
      - If an [808]/[318] sits right after an [HSS-FULL] line with no [BOOT],
        [DRV] or [USB] near it -> the HSS full apply is a TRIGGER.
      - If it sits after [BOOT], [DRV] or [USB] -> boot / driver / device
        driven, not HSS.
      - If the only HSS line near it is [HSS-NOOP] -> HSS did nothing then;
        look at the other signals.

    Also reports when the box went to its current Windows build and the
    earliest 808/318 ever recorded.

    ONLY READS. No changes. Console + transcript.

.PARAMETER SinceDays
    How far back to look. Default 14.

.NOTES
    SuperOps (SYSTEM). Self-contained. PS 5.1-safe. No automated tests.
#>

param(
    [int]$SinceDays = 14
)

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "PrinterBlockTimeline-$env:COMPUTERNAME.log"
function Write-Log {
    param([string]$m)
    Write-Host $m
    try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {
        Write-Host "WARN: failed to append to transcript '$transcript': $($_.Exception.Message)"
    }
}
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {
    Write-Host "WARN: failed to reset transcript '$transcript': $($_.Exception.Message)"
}

$since = (Get-Date).AddDays(-$SinceDays)
$printAdminLog = 'Microsoft-Windows-PrintService/Admin'

Write-Log "Printer-block / settings-reset timeline correlation"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Window      : last $SinceDays days (since $($since.ToString('yyyy-MM-dd HH:mm')))"

# Collect timeline rows as objects { Time (datetime), Type, Detail }.
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row { param([datetime]$Time,[string]$Type,[string]$Detail)
    $rows.Add([pscustomobject]@{ Time = $Time; Type = $Type; Detail = $Detail })
}
function Get-ShortText { param([string]$Text,[int]$Max = 110)
    $t = ("$Text" -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) }
    return $t
}

# --- BOOTS (Event Log service started = 6005, close proxy for boot) ----------
try {
    $boots = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=6005; StartTime=$since } -ErrorAction Stop
    foreach ($b in $boots) { Add-Row $b.TimeCreated 'BOOT' 'system start (EventLog 6005)' }
} catch {
    Write-Log "WARN: System/EventLog 6005 boot query failed: $($_.Exception.Message)"
}
# Also Kernel-Boot 27 / Kernel-General 12 as backup signal.
try {
    $k = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12; StartTime=$since } -ErrorAction Stop
    foreach ($e in $k) { Add-Row $e.TimeCreated 'BOOT' 'OS started (Kernel-General 12)' }
} catch {
    Write-Log "WARN: Kernel-General 12 boot query failed: $($_.Exception.Message)"
}

# --- HSS apply runs (parse the apply log + customize log) --------------------
# Lines look like: [yyyy-MM-dd HH:mm:ss] [user] message
# Classify each marker, because a hash-match run is a sub-second no-op that
# never calls ImportReport. Note "skip ImportReport" is a NO-OP line, so the
# FULL regex must not match on the bare word ImportReport.
$hssLogs = @(
    'C:\Temp\Apply-HardenSystemSecurityReport.log',
    'C:\Temp\Customization.log'
)
$tsRegex = '^\[?(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})'
foreach ($lf in $hssLogs) {
    if (-not (Test-Path -LiteralPath $lf)) { continue }
    try {
        $lines = Get-Content -LiteralPath $lf -ErrorAction Stop
    } catch {
        Write-Log "WARN: HSS log read failed for '$lf': $($_.Exception.Message)"
        continue
    }
    foreach ($line in $lines) {
        $type = $null
        if ($line -match 'Hash matches') { $type = 'HSS-NOOP' }
        elseif ($line -match 'Applying via|Apply succeeded|Apply failed') { $type = 'HSS-FULL' }
        elseif ($line -match 'Apply task fired|Triggered .*Apply-HardenSystemSecurityReport') { $type = 'HSS-RUN' }
        if (-not $type) { continue }
        $m = [regex]::Match($line, $tsRegex)
        if (-not $m.Success) { continue }
        $t = $null
        try { $t = [datetime]::Parse($m.Groups[1].Value) } catch { $t = $null }
        if ($t -and $t -ge $since) {
            $short = Get-ShortText ($line -replace $tsRegex, '') 80
            Add-Row $t $type ("{0}: {1}" -f (Split-Path $lf -Leaf), $short)
        }
    }
}
# Plus the single HKLM "last applied" marker (only written by a FULL apply).
try {
    $lastUtc = (Get-ItemProperty 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity' -Name LastAppliedUtc -ErrorAction Stop).LastAppliedUtc
    $t = $null
    try { $t = ([datetimeoffset]::Parse($lastUtc)).LocalDateTime } catch { $t = $null }
    if ($t -and $t -ge $since) { Add-Row $t 'HSS-FULL' 'HKLM LastAppliedUtc (end of last successful full apply)' }
} catch {
    Write-Log "WARN: LastAppliedUtc read failed: $($_.Exception.Message)"
}

# --- Spooler start/stop (System 7036) -----------------------------------------
# The message text is localized; the Binary data is the UTF-16 service name
# plus "/<state>", e.g. "Spooler/4" (4 = running, 1 = stopped).
try {
    $scm = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Service Control Manager'; Id=7036; StartTime=$since } -ErrorAction Stop
    foreach ($e in $scm) {
        $hex = $null
        try { $hex = ([xml]$e.ToXml()).Event.EventData.Binary } catch { $hex = $null }
        if (-not $hex -or ($hex.Length % 2) -ne 0) { continue }
        $bytes = New-Object byte[] ($hex.Length / 2)
        for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
        $svc = [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
        if ($svc -notmatch '^Spooler/(\d+)') { continue }
        $state = switch ($Matches[1]) { '4' { 'running' } '1' { 'stopped' } default { "state $($Matches[1])" } }
        Add-Row $e.TimeCreated 'SPOOL' "Print Spooler $state (SCM 7036)"
    }
} catch {
    Write-Log "WARN: Service Control Manager 7036 query failed: $($_.Exception.Message)"
}

# --- Driver installs / updates ------------------------------------------------
try {
    $drv = Get-WinEvent -FilterHashtable @{ LogName=$printAdminLog; Id=316; StartTime=$since } -ErrorAction Stop
    foreach ($e in $drv) { Add-Row $e.TimeCreated 'DRV' ("PrintService 316: " + (Get-ShortText $e.Message 95)) }
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') {
        Write-Log "WARN: PrintService/Admin 316 query failed: $($_.Exception.Message)"
    }
}
try {
    $pnp = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-UserPnp'; Id=@(20001, 20003); StartTime=$since } -ErrorAction Stop
    foreach ($e in $pnp) {
        if ("$($e.Message)" -notmatch 'USBPRINT|VID_0A5F|ZDesigner|Zebra|prn') { continue }
        Add-Row $e.TimeCreated 'DRV' ("UserPnp $($e.Id): " + (Get-ShortText $e.Message 95))
    }
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') {
        Write-Log "WARN: UserPnp 20001/20003 query failed: $($_.Exception.Message)"
    }
}

# --- USB printer device arrivals (printer swap / replug) ----------------------
try {
    $kp = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Kernel-PnP/Configuration'; Id=@(400, 410); StartTime=$since } -ErrorAction Stop
    foreach ($e in $kp) {
        $msg = "$($e.Message)"
        if ($msg -notmatch 'VID_0A5F|USBPRINT') { continue }
        $dev = [regex]::Match($msg, '((?:USB|USBPRINT|SWD)\\[^\s]+)', 'IgnoreCase')
        $what = if ($dev.Success) { $dev.Groups[1].Value } else { Get-ShortText $msg 80 }
        Add-Row $e.TimeCreated 'USB' ("Kernel-PnP $($e.Id): $what")
    }
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') {
        Write-Log "WARN: Kernel-PnP/Configuration 400/410 query failed: $($_.Exception.Message)"
    }
}

# --- 808 bursts (collapse into 10-minute buckets) ----------------------------
$blocks = @()
try {
    $blocks = Get-WinEvent -FilterHashtable @{ LogName=$printAdminLog; Id=808; StartTime=$since } -ErrorAction Stop
} catch {
    Write-Log "WARN: PrintService/Admin 808 query failed for analysis window: $($_.Exception.Message)"
}
$earliest808Overall = $null
try {
    $firstBlock = Get-WinEvent -FilterHashtable @{ LogName=$printAdminLog; Id=808 } -Oldest -MaxEvents 1 -ErrorAction Stop
    if ($firstBlock) { $earliest808Overall = $firstBlock.TimeCreated }
} catch {
    Write-Log "WARN: earliest PrintService/Admin 808 query failed: $($_.Exception.Message)"
}

# Bucket the in-window blocks by 10-min slot.
$buckets = @{}
foreach ($e in $blocks) {
    $slotKey = $e.TimeCreated.ToString('yyyy-MM-dd HH:') + ('{0:D2}' -f ([int]([math]::Floor($e.TimeCreated.Minute / 10) * 10)))
    if (-not $buckets.ContainsKey($slotKey)) {
        $dll = ''
        $mm = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        if ($mm.Success) { $dll = $mm.Groups[1].Value }
        $buckets[$slotKey] = [pscustomobject]@{ Time=$e.TimeCreated; Count=0; Dll=$dll }
    }
    $buckets[$slotKey].Count++
}
foreach ($b in $buckets.Values) {
    Add-Row $b.Time '808' ("x$($b.Count) block(s), e.g. $($b.Dll)")
}

# --- 318 printer-settings resets (one row per event; they are rare) ----------
$resets = @()
try {
    $resets = @(Get-WinEvent -FilterHashtable @{ LogName=$printAdminLog; Id=318; StartTime=$since } -ErrorAction Stop)
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') {
        Write-Log "WARN: PrintService/Admin 318 query failed for analysis window: $($_.Exception.Message)"
    }
}
$earliest318Overall = $null
try {
    $first318 = Get-WinEvent -FilterHashtable @{ LogName=$printAdminLog; Id=318 } -Oldest -MaxEvents 1 -ErrorAction Stop
    if ($first318) { $earliest318Overall = $first318.TimeCreated }
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') {
        Write-Log "WARN: earliest PrintService/Admin 318 query failed: $($_.Exception.Message)"
    }
}
foreach ($e in $resets) {
    $ud = ''
    try { $ud = ([xml]$e.ToXml()).Event.UserData.InnerText } catch { $ud = '' }
    $src = "$($e.Message) $ud"
    $zebra = if ($src -match 'ZDesigner|Zebra') { 'ZEBRA ' } else { '' }
    $err = [regex]::Match("$($e.Message)", 'Error:\s*(\d+)')
    $errText = if ($err.Success) { " err=$($err.Groups[1].Value)" } else { '' }
    Add-Row $e.TimeCreated '318' ("$zebra" + "settings reset$errText : " + (Get-ShortText $e.Message 90))
}

# --- Merged chronological timeline -------------------------------------------
Write-Section "Merged timeline (last $SinceDays days) - read cause/effect alignment"
Write-Log "TIME                  TYPE      DETAIL"
Write-Log "--------------------  --------  ------"
$sorted = $rows | Sort-Object Time
if ($sorted) {
    foreach ($r in $sorted) {
        Write-Log ("{0}  {1,-8}  {2}" -f $r.Time.ToString('yyyy-MM-dd HH:mm:ss'), $r.Type, $r.Detail)
    }
} else {
    Write-Log "(no boot/HSS/spooler/driver/808/318 events in window)"
}

$bootTimes    = @($rows | Where-Object { $_.Type -eq 'BOOT' }     | Select-Object -ExpandProperty Time)
$hssFullTimes = @($rows | Where-Object { $_.Type -eq 'HSS-FULL' } | Select-Object -ExpandProperty Time)
$hssNoopTimes = @($rows | Where-Object { $_.Type -eq 'HSS-NOOP' } | Select-Object -ExpandProperty Time)
$blkTimes     = @($rows | Where-Object { $_.Type -eq '808' }      | Select-Object -ExpandProperty Time)
function Near { param([datetime]$t,[datetime[]]$set,[int]$mins=15)
    foreach ($s in $set) { if ([math]::Abs(($t - $s).TotalMinutes) -le $mins) { return $true } }
    return $false
}

# --- Verdict helper: is any 808 burst close to an HSS FULL apply but NOT a boot?
# Only full applies count: a hash-match no-op never reaches the spooler.
Write-Section 'Auto-read 808: do plug-in blocks align with HSS full applies, with boots, or both?'
$nBoot=0; $nHssOnly=0; $nNeither=0
foreach ($bt in $blkTimes) {
    $nearBoot = Near $bt $bootTimes 15
    $nearHss  = Near $bt $hssFullTimes 15
    if ($nearBoot) { $nBoot++ }
    elseif ($nearHss) { $nHssOnly++ }
    else { $nNeither++ }
}
Write-Log "808 bursts in window                : $($blkTimes.Count)"
Write-Log "  near a BOOT (<=15min)             : $nBoot"
Write-Log "  near an HSS FULL apply, NOT a boot : $nHssOnly   <-- if >0, HSS apply is a trigger"
Write-Log "  near neither                      : $nNeither"
Write-Log "HSS full applies in window: $($hssFullTimes.Count)   HSS no-op runs: $($hssNoopTimes.Count)"
Write-Log ''
if ($nHssOnly -gt 0) {
    Write-Log "READ: at least one 808 burst fired next to an HSS full apply with no nearby boot"
    Write-Log "      -> the HSS apply IS a trigger for the block on this box."
} elseif ($nBoot -gt 0 -and $hssFullTimes.Count -gt 0) {
    Write-Log "READ: 808 bursts align with boots, not with lone HSS full applies"
    Write-Log "      -> block is boot/OS-driven here; HSS runs alone did not trigger it."
} else {
    Write-Log "READ: inconclusive (not enough HSS full applies or boots in the window to separate them)."
}

# --- Verdict helper: what preceded each Event 318 settings reset? ------------
# A cause must come BEFORE the reset, so look back 15 minutes (plus 1 minute
# forward for log-timestamp slop, e.g. HKLM LastAppliedUtc is written at the
# END of the apply). Every nearby signal is listed rather than picking one, so
# a mixed case (boot + HSS in the same window) is visible as mixed.
Write-Section 'Auto-read 318: what preceded each printer-settings reset?'
$causeTypes = @('BOOT', 'HSS-FULL', 'HSS-NOOP', 'SPOOL', 'DRV', 'USB')
$resetRows = @($rows | Where-Object { $_.Type -eq '318' } | Sort-Object Time)
$n318 = @{ HSS = 0; BOOT = 0; DRIVER = 0; SPOOL = 0; NOOP = 0; NONE = 0 }
if ($resetRows.Count -eq 0) {
    Write-Log "No Event 318 in window."
}
foreach ($r in $resetRows) {
    $near = @($rows | Where-Object {
        $_.Type -in $causeTypes -and
        ($r.Time - $_.Time).TotalMinutes -le 15 -and
        ($r.Time - $_.Time).TotalMinutes -ge -1
    } | Sort-Object Time)
    $types = @($near | Select-Object -ExpandProperty Type -Unique)

    if ($types -contains 'DRV' -or $types -contains 'USB') { $verdict = 'DRIVER/DEVICE install or arrival'; $n318.DRIVER++ }
    elseif ($types -contains 'BOOT') { $verdict = 'BOOT'; $n318.BOOT++ }
    elseif ($types -contains 'HSS-FULL') { $verdict = 'HSS FULL APPLY (no boot/driver/device signal nearby)'; $n318.HSS++ }
    elseif ($types -contains 'SPOOL') { $verdict = 'SPOOLER RESTART (not boot, not an HSS full apply)'; $n318.SPOOL++ }
    elseif ($types -contains 'HSS-NOOP') { $verdict = 'only an HSS NO-OP run nearby - HSS did not apply, look elsewhere'; $n318.NOOP++ }
    else { $verdict = 'UNEXPLAINED (no boot/HSS/spooler/driver/device signal in the 15 min before)'; $n318.NONE++ }

    Write-Log ''
    Write-Log ("318 at {0}  {1}" -f $r.Time.ToString('yyyy-MM-dd HH:mm:ss'), $r.Detail)
    if ($near.Count -eq 0) {
        Write-Log "    (nothing in the preceding 15 min)"
    }
    foreach ($n in $near) {
        $delta = [int][math]::Round(($r.Time - $n.Time).TotalSeconds)
        Write-Log ("    {0,7}  {1,-8}  {2}" -f "-${delta}s", $n.Type, $n.Detail)
    }
    if (@($types | Where-Object { $_ -in @('BOOT', 'HSS-FULL', 'DRV', 'USB') }).Count -gt 1) {
        $verdict = "$verdict  [MIXED: $($types -join ', ') - not separable from this box alone]"
    }
    Write-Log "    READ: $verdict"
}
if ($resetRows.Count -gt 0) {
    Write-Log ''
    Write-Log "318 resets in window                    : $($resetRows.Count)"
    Write-Log "  after a driver/device install/arrival : $($n318.DRIVER)"
    Write-Log "  after a boot                          : $($n318.BOOT)"
    Write-Log "  after an HSS FULL apply only          : $($n318.HSS)   <-- if >0, HSS apply is a trigger for resets"
    Write-Log "  after a plain spooler restart only    : $($n318.SPOOL)"
    Write-Log "  after an HSS no-op only               : $($n318.NOOP)"
    Write-Log "  unexplained                           : $($n318.NONE)"
}

# --- Context: build/feature-update date + earliest-ever 808/318 --------------
Write-Section 'Context: when did this box go 24H2/25H2, and when did 808s/318s first appear?'
try {
    $ci = Get-ComputerInfo -Property OsName,OsVersion,WindowsVersion,OsBuildNumber,OsInstallDate -ErrorAction Stop
    Write-Log "OS               : $($ci.OsName)  $($ci.WindowsVersion)  build $($ci.OsBuildNumber)"
    Write-Log "OS install date  : $($ci.OsInstallDate)   (feature-update/clean-install time for current build)"
} catch {
    Write-Log "Get-ComputerInfo failed: $_"
}
if ($earliest808Overall) {
    Write-Log "Earliest 808 ever: $($earliest808Overall.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "  -> if this PREDATES recent HSS rollout, the block isn't new-from-HSS."
} else {
    Write-Log "Earliest 808 ever: (none found)"
}
if ($earliest318Overall) {
    Write-Log "Earliest 318 ever: $($earliest318Overall.ToString('yyyy-MM-dd HH:mm:ss'))"
} else {
    Write-Log "Earliest 318 ever: (none found)"
}
Write-Log "HSS apply log    : C:\Temp\Apply-HardenSystemSecurityReport.log (FULL vs NO-OP is only visible here)"

Write-Section 'Timeline complete (read-only - no changes made)'
Write-Log "Transcript: $transcript"
