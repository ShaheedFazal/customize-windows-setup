<#
.SYNOPSIS
    Read-only TIMELINE correlation for ONE blocked box: does the Event 808
    plug-in-block wave line up with HSS apply runs, or only with reboots?
    This is the test that separates "HSS triggers it" from "it's just the
    Windows 11 24H2 print engine firing at every boot".

.DESCRIPTION
    Builds a single merged chronological timeline over the last 14 days of:
      [BOOT]  - system start (Event Log 6005 / Kernel-Boot)
      [HSS]   - HSS apply-task runs (parsed from the apply log + customize log)
      [808]   - print spooler plug-in-block bursts (PrintService/Admin Id 808),
                collapsed into ~10-minute buckets with a count

    READ THE TIMELINE:
      - If an [808] burst sits right after an [HSS] line with NO [BOOT] near it
        -> the HSS apply is a TRIGGER for the block.
      - If every [808] burst sits right after a [BOOT] and never next to a
        lone [HSS] -> the block is boot/OS-driven, not HSS.

    Also reports when the box went to its current build (24H2/25H2 feature
    update) and the earliest 808 ever recorded, to see whether blocks predate
    recent hardening runs.

    ONLY READS. No changes. Console + transcript. Run on a box showing
    PrintBlock_Status = BLOCKED with a recent PrintBlock_LastUtc.

.NOTES
    SuperOps (SYSTEM). Self-contained. PS 5.1-safe. No automated tests.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "PrinterBlockTimeline-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$sinceDays = 14
$since = (Get-Date).AddDays(-$sinceDays)

Write-Log "Printer-block timeline correlation"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Window      : last $sinceDays days (since $($since.ToString('yyyy-MM-dd HH:mm')))"

# Collect timeline rows as objects { Time (datetime), Type, Detail }.
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row { param([datetime]$Time,[string]$Type,[string]$Detail)
    $rows.Add([pscustomobject]@{ Time = $Time; Type = $Type; Detail = $Detail })
}

# --- BOOTS (Event Log service started = 6005, close proxy for boot) ----------
try {
    $boots = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=6005; StartTime=$since } -ErrorAction Stop
    foreach ($b in $boots) { Add-Row $b.TimeCreated 'BOOT' 'system start (EventLog 6005)' }
} catch { }
# Also Kernel-Boot 27 / Kernel-General 12 as backup signal.
try {
    $k = Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12; StartTime=$since } -ErrorAction Stop
    foreach ($e in $k) { Add-Row $e.TimeCreated 'BOOT' 'OS started (Kernel-General 12)' }
} catch { }

# --- HSS apply runs (parse the apply log + customize log) --------------------
# Lines look like: [yyyy-MM-dd HH:mm:ss] [user] message
$hssLogs = @(
    'C:\Temp\Apply-HardenSystemSecurityReport.log',
    'C:\Temp\Customization.log'
)
$tsRegex = '^\[?(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})'
foreach ($lf in $hssLogs) {
    if (-not (Test-Path -LiteralPath $lf)) { continue }
    try {
        $lines = Get-Content -LiteralPath $lf -ErrorAction Stop
    } catch { continue }
    foreach ($line in $lines) {
        # Only the meaningful apply markers, to avoid flooding the timeline.
        if ($line -notmatch 'Apply task fired|Applying via|Apply succeeded|Apply failed|Hash matches|ImportReport') { continue }
        $m = [regex]::Match($line, $tsRegex)
        if (-not $m.Success) { continue }
        $t = $null
        if ([datetime]::TryParse($m.Groups[1].Value, [ref]$t)) {
            if ($t -ge $since) {
                $short = ($line -replace $tsRegex, '').Trim()
                if ($short.Length -gt 60) { $short = $short.Substring(0,60) }
                Add-Row $t 'HSS' (Split-Path $lf -Leaf)
            }
        }
    }
}
# Plus the single HKLM "last applied" marker (may be outside the parsed logs).
try {
    $lastUtc = (Get-ItemProperty 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity' -Name LastAppliedUtc -ErrorAction Stop).LastAppliedUtc
    $t = $null
    if ([datetime]::TryParse($lastUtc, [ref]$t)) {
        $tl = $t.ToLocalTime()
        if ($tl -ge $since) { Add-Row $tl 'HSS' 'HKLM LastAppliedUtc' }
    }
} catch { }

# --- 808 bursts (collapse into 10-minute buckets) ----------------------------
$blocks = @()
try {
    $blocks = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PrintService/Admin'; Id=808; StartTime=$since } -ErrorAction Stop
} catch { }
$earliest808Overall = $null
try {
    $allBlocks = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PrintService/Admin'; Id=808 } -MaxEvents 1000 -ErrorAction Stop |
        Sort-Object TimeCreated
    if ($allBlocks) { $earliest808Overall = $allBlocks[0].TimeCreated }
} catch { }

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

# --- Merged chronological timeline -------------------------------------------
Write-Section "Merged timeline (last $sinceDays days) - read BOOT/HSS/808 alignment"
Write-Log "TIME                  TYPE   DETAIL"
Write-Log "--------------------  -----  ------"
$sorted = $rows | Sort-Object Time
if ($sorted) {
    foreach ($r in $sorted) {
        Write-Log ("{0}  {1,-5}  {2}" -f $r.Time.ToString('yyyy-MM-dd HH:mm:ss'), $r.Type, $r.Detail)
    }
} else {
    Write-Log "(no boot/HSS/808 events in window)"
}

# --- Verdict helper: is any 808 burst close to an HSS run but NOT a boot? -----
Write-Section 'Auto-read: do 808 bursts align with HSS, with boots, or both?'
$bootTimes = @($rows | Where-Object { $_.Type -eq 'BOOT' } | Select-Object -ExpandProperty Time)
$hssTimes  = @($rows | Where-Object { $_.Type -eq 'HSS'  } | Select-Object -ExpandProperty Time)
$blkTimes  = @($rows | Where-Object { $_.Type -eq '808'  } | Select-Object -ExpandProperty Time)
function Near { param([datetime]$t,[datetime[]]$set,[int]$mins=15)
    foreach ($s in $set) { if ([math]::Abs(($t - $s).TotalMinutes) -le $mins) { return $true } }
    return $false
}
$nBoot=0; $nHssOnly=0; $nNeither=0
foreach ($bt in $blkTimes) {
    $nearBoot = Near $bt $bootTimes 15
    $nearHss  = Near $bt $hssTimes 15
    if ($nearBoot) { $nBoot++ }
    elseif ($nearHss) { $nHssOnly++ }
    else { $nNeither++ }
}
Write-Log "808 bursts in window      : $($blkTimes.Count)"
Write-Log "  near a BOOT (<=15min)   : $nBoot"
Write-Log "  near an HSS run, NOT a boot : $nHssOnly   <-- if >0, HSS apply is a trigger"
Write-Log "  near neither            : $nNeither"
Write-Log ''
if ($nHssOnly -gt 0) {
    Write-Log "READ: at least one 808 burst fired next to an HSS apply with no nearby boot"
    Write-Log "      -> the HSS apply IS a trigger for the block on this box."
} elseif ($nBoot -gt 0 -and $hssTimes.Count -gt 0) {
    Write-Log "READ: 808 bursts align with boots, not with lone HSS runs"
    Write-Log "      -> block is boot/OS-driven here; HSS runs alone did not trigger it."
} else {
    Write-Log "READ: inconclusive (not enough HSS runs or boots in the window to separate them)."
}

# --- Context: build/feature-update date + earliest-ever 808 ------------------
Write-Section 'Context: when did this box go 24H2/25H2, and when did 808s first appear?'
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

Write-Section 'Timeline complete (read-only - no changes made)'
Write-Log "Transcript: $transcript"
