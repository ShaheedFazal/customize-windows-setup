<#
.SYNOPSIS
    Read-only SuperOps monitor for Harden System Security rollout state and
    printer-stack health.

.DESCRIPTION
    Emits ONE pipe-delimited SUMMARY line per endpoint for fleet aggregation,
    then a short human-readable detail block. Reports:
      - OS build
      - Harden System Security apply state, version, report hash, and exit code
      - Windows Protected Print Mode (WPP) policy and effective state
      - current PrintService/Admin Event 808 plug-in-load blocks after latest
        HSS apply, plus historical block context in the transcript
      - printer queue count and non-Normal printer count
      - Zebra label queue settings: Event 318 DEVMODE resets and whether the
        Printing Defaults / signed-in users' Printing Preferences are at the
        4x6in driver default (ZebraSettings_* fields)
      - SuperOps custom fields for dashboard filtering

    Read-only: no registry/driver/printer/service/policy changes.

.NOTES
    SuperOps (SYSTEM). Self-contained. No automated tests (AGENTS.md).
#>

$ErrorActionPreference = 'Continue'

# If HSS has never recorded an apply time, events newer than this window are
# treated as current. If HSS has applied, "current" means after LastAppliedUtc.
$CurrentBlockWindowHours = 2

# Import the SuperOps module so Send-CustomField is available. SuperOps injects
# the $SuperOpsModule variable into the script runtime (both run-now and
# scheduled). Without this, Send-CustomField is undefined and the custom-field
# push is silently skipped. Guarded so the script still runs outside SuperOps.
if ($SuperOpsModule) {
    try { Import-Module $SuperOpsModule -ErrorAction Stop } catch {
        Write-Warning "Import-Module failed for '$SuperOpsModule': $($_.Exception.Message)"
    }
}

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "HSSPrinterHealth-$env:COMPUTERNAME.log"
function Write-Log {
    param([string]$m)
    Write-Host $m
    try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {
        Write-Warning "Transcript append failed for '$transcript': $($_.Exception.Message)"
    }
}
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {
    Write-Warning "Transcript cleanup failed for '$transcript': $($_.Exception.Message)"
}

# --- OS version / build ------------------------------------------------------
$os      = try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $null }
$caption = if ($os) { ($os.Caption -replace '^Microsoft\s+', '').Trim() } else { '?' }   # e.g. "Windows 11 Pro"
$build   = if ($os) { $os.BuildNumber } else { '?' }
$cvKey   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$ubr     = try { (Get-ItemProperty $cvKey -Name UBR -ErrorAction Stop).UBR } catch { '?' }
$display = try { (Get-ItemProperty $cvKey -Name DisplayVersion -ErrorAction Stop).DisplayVersion } catch { $null }
if (-not $display) { $display = try { (Get-ItemProperty $cvKey -Name ReleaseId -ErrorAction Stop).ReleaseId } catch { '?' } }
# Concise version string, e.g. "Windows 11 Pro 25H2 (26200.1234)"
$winVer = "$caption $display ($build.$ubr)"

# --- WPP state ---------------------------------------------------------------
# Policy value (GPO/MDM) and effective/local value live in different keys.
function Get-RegVal { param([string]$Path,[string]$Name)
    try { return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}
$wppPolicy = Get-RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP' 'WindowsProtectedPrintMode'
$wppLocal  = Get-RegVal 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\WPP' 'WindowsProtectedPrintMode'
$wppEnby   = Get-RegVal 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\WPP' 'EnabledBy'
# Effective = local if set, else policy, else 0/unknown.
$wppEff = if ($null -ne $wppLocal) { $wppLocal } elseif ($null -ne $wppPolicy) { $wppPolicy } else { 'unset' }
$wppOn  = ($wppEff -eq 1)
$wppOnText = if ($wppOn) { 'ON' } else { 'OFF' }

# --- Event 808 plug-in load blocks ------------------------------------------
# We collect recent Event 808 records first, then classify them after HSS state
# is known. Dashboard fields are current-only; historical events are retained in
# the SUMMARY/transcript for context.
$blockCount = 0; $dlls = @(); $codes = @(); $lastBlock = ''; $events = @()
$logName     = 'Microsoft-Windows-PrintService/Admin'
$logReadable = $false
try {
    $logInfo = Get-WinEvent -ListLog $logName -ErrorAction Stop
    if ($logInfo.IsEnabled) { $logReadable = $true }
} catch { $logReadable = $false }

if ($logReadable) {
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 808 } `
            -MaxEvents 200 -ErrorAction SilentlyContinue
        )
    } catch {
        $events = @()
        $logReadable = $false
        Write-Log "Event query failed for $logName/808: $($_.Exception.Message)"
    }
    if ($events) {
        $blockCount = @($events).Count
        $lastBlock  = $events[0].TimeCreated.ToString('yyyy-MM-dd HH:mm')
        foreach ($e in $events) {
            $ud = ''
            try { $ud = ([xml]$e.ToXml()).Event.UserData.InnerXml } catch {
                Write-Log "Event XML parse failed for $logName/808 RecordId $($e.RecordId): $($_.Exception.Message)"
            }
            # Pull the DLL leaf name and the 0x.... code from the message/userdata.
            $src = "$($e.Message) $ud"
            $m = [regex]::Match($src, '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
            if ($m.Success) { $dlls += $m.Groups[1].Value }
            $c = [regex]::Match($src, '0x[0-9A-Fa-f]{1,8}')
            if ($c.Success) { $codes += $c.Value }
        }
    }
}
$dllList  = ($dlls  | Sort-Object -Unique) -join ','
$codeList = ($codes | Sort-Object -Unique) -join ','
if (-not $dllList)  { $dllList  = '-' }
if (-not $codeList) { $codeList = '-' }

# Classify vendors from the DLL names for a quick read.
$vendors = @()
if ($dllList -match 'ZDesigner|ZDN|zdn') { $vendors += 'Zebra' }
if ($dllList -match 'BRU|brother|broh') { $vendors += 'Brother' }
if ($dllList -match 'Epson|EPSON|E_[A-Za-z0-9_]+\.DLL|EFX') { $vendors += 'Epson' }
if ($dllList -match 'BIXOLON|Bixolon|BX|XD5|SLP|SRP') { $vendors += 'Bixolon' }
if ($dllList -match 'star|tsp|tup') { $vendors += 'Star' }
$vendorList = if ($vendors) { ($vendors | Sort-Object -Unique) -join ',' } else { '-' }

# --- Printer queues ----------------------------------------------------------
$prnTotal = 0; $prnBad = 0; $prnNames = '-'
try {
    $prn = Get-Printer -ErrorAction Stop
    $prnTotal = @($prn).Count
    $bad = @($prn | Where-Object { $_.PrinterStatus -ne 'Normal' })
    $prnBad = $bad.Count
    $prnNames = (@($prn | Select-Object -ExpandProperty Name) -join ';')
    if (-not $prnNames) { $prnNames = '-' }
} catch { $prnNames = "ERR:$_" }

# --- HSS apply state ---------------------------------------------------------
# Has our hardening stack actually run on this endpoint? Key written by the
# Apply-HSS scheduled task (see Ensure-Apps.ps1). This is the primary rollout
# state used by the monitor.
$hssStatus = '-'; $hssWhen = '-'; $hssHash = '-'; $hssVer = '-'; $hssExit = '-'
$hssKey = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$s = Get-RegVal $hssKey 'LastAppliedStatus';   if ($s) { $hssStatus = $s }
$w = Get-RegVal $hssKey 'LastAppliedUtc';      if ($w) { $hssWhen   = $w }
$h = Get-RegVal $hssKey 'ReportHash';          if ($h) { $hssHash   = ($h.Substring(0, [Math]::Min(12, $h.Length))) }
$v = Get-RegVal $hssKey 'AppliedHssVersion';   if ($v) { $hssVer    = $v }
$x = Get-RegVal $hssKey 'LastAppliedExitCode'; if ($null -ne $x) { $hssExit = $x }
# 'hss_ran' is the clean yes/no: did HSS actually complete an apply here?
# States such as pending-install mean the monitor/task exists, but HSS has not
# successfully applied a report on this endpoint yet.
$hssRan = ($hssWhen -ne '-')

$hssAppliedAt = $null
if ($hssWhen -ne '-') {
    try { $hssAppliedAt = [datetimeoffset]::Parse($hssWhen).LocalDateTime } catch { $hssAppliedAt = $null }
}

# Current = blocks after latest HSS apply. If HSS has no parseable apply time,
# use a short rolling window so stale historical events do not keep an endpoint
# flagged forever.
$currentSince = if ($hssAppliedAt) { $hssAppliedAt } else { (Get-Date).AddHours(-1 * $CurrentBlockWindowHours) }
$currentEvents = @()
if ($logReadable -and $events) {
    $currentEvents = @($events | Where-Object { $_.TimeCreated -ge $currentSince })
}
$currentBlockCount = $currentEvents.Count
$historicalBlockCount = [Math]::Max(0, $blockCount - $currentBlockCount)
$currentSinceText = $currentSince.ToString('yyyy-MM-dd HH:mm')

$currentDlls = @()
$currentCodes = @()
$currentLastBlock = '-'
if ($currentEvents.Count -gt 0) {
    $currentLastBlock = $currentEvents[0].TimeCreated.ToString('yyyy-MM-dd HH:mm')
    foreach ($e in $currentEvents) {
        $ud = ''
        try { $ud = ([xml]$e.ToXml()).Event.UserData.InnerXml } catch {}
        $src = "$($e.Message) $ud"
        $m = [regex]::Match($src, '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        if ($m.Success) { $currentDlls += $m.Groups[1].Value }
        $c = [regex]::Match($src, '0x[0-9A-Fa-f]{1,8}')
        if ($c.Success) { $currentCodes += $c.Value }
    }
}
$currentDllList = ($currentDlls | Sort-Object -Unique) -join ','
$currentCodeList = ($currentCodes | Sort-Object -Unique) -join ','
if (-not $currentDllList) { $currentDllList = '-' }
if (-not $currentCodeList) { $currentCodeList = '-' }

$currentVendors = @()
if ($currentDllList -match 'ZDesigner|ZDN|zdn') { $currentVendors += 'Zebra' }
if ($currentDllList -match 'BRU|brother|broh') { $currentVendors += 'Brother' }
if ($currentDllList -match 'Epson|EPSON|E_[A-Za-z0-9_]+\.DLL|EFX') { $currentVendors += 'Epson' }
if ($currentDllList -match 'BIXOLON|Bixolon|BX|XD5|SLP|SRP') { $currentVendors += 'Bixolon' }
if ($currentDllList -match 'star|tsp|tup') { $currentVendors += 'Star' }
$currentVendorList = if ($currentVendors) { ($currentVendors | Sort-Object -Unique) -join ',' } else { '-' }

# Current-only status for dashboards:
#   BLOCKED_CURRENT = 808 block happened after latest HSS apply / current window
#   CLEAN           = no current block evidence, even if historical blocks exist
#   UNKNOWN         = log disabled or unreadable
if (-not $logReadable) {
    $printBlockStatus = 'UNKNOWN'
} elseif ($currentBlockCount -gt 0) {
    $printBlockStatus = 'BLOCKED_CURRENT'
} else {
    $printBlockStatus = 'CLEAN'
}

# --- Zebra label settings: Event 318 DEVMODE reset ----------------------------
# Event 318 ("Failed to upgrade printer settings ... set to those configured by
# the manufacturer") resets a queue's saved settings to the driver default. For
# ZDesigner that is 4x6in, which puts a printer loaded with smaller label stock
# into media-out while Windows still shows the queue as Normal. The event is a
# one-shot, so the dashboard status is driven by the settings as they are NOW:
#   DEFAULT_SIZE = Printing Defaults or a signed-in user's Printing Preferences
#                  decode as 4x6in (alert)
#   RESET_RECENT = a Zebra 318 in the last $RecentResetHours but sizes are not
#                  the default any more (someone fixed it; context)
#   OK / NO_ZEBRA / UNKNOWN
# Per-user preferences are only readable for users whose hive is loaded
# (signed in); Titan prints as its own Windows user, so run while it is signed in.
$RecentResetHours = 24
function Get-DevModeSize { param([byte[]]$Bytes)
    # DEVMODEW dmPaperLength @80, dmPaperWidth @82, both in 0.1 mm.
    if (-not $Bytes -or $Bytes.Length -lt 84) { return $null }
    $len = [BitConverter]::ToInt16($Bytes, 80); $wid = [BitConverter]::ToInt16($Bytes, 82)
    [pscustomobject]@{
        Text      = '{0}x{1}' -f ($wid / 10.0), ($len / 10.0)
        IsDefault = (($wid -eq 1016 -and $len -eq 1524) -or ($wid -eq 1524 -and $len -eq 1016))
    }
}
$zebraQueues = @()
try { $zebraQueues = @(Get-Printer -ErrorAction Stop | Where-Object { $_.Name -match 'ZDesigner|Zebra' -or $_.DriverName -match 'ZDesigner|Zebra' }) } catch {}
$zebraDetail = @(); $zebraAnyDefault = $false
$loadedUsers = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' })
foreach ($zq in $zebraQueues) {
    $parts = @()
    $gBytes = $null
    try { $gBytes = (Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\' + ($zq.Name -replace '\\', ',')) -Name 'Default DevMode' -ErrorAction Stop).'Default DevMode' } catch {}
    $g = Get-DevModeSize $gBytes
    if ($g) { $parts += "defaults=$($g.Text)"; if ($g.IsDefault) { $zebraAnyDefault = $true } } else { $parts += 'defaults=?' }
    foreach ($hive in $loadedUsers) {
        $uBytes = $null
        try { $uBytes = (Get-ItemProperty -LiteralPath "Registry::HKEY_USERS\$($hive.PSChildName)\Printers\DevModePerUser" -Name $zq.Name -ErrorAction Stop).($zq.Name) } catch {}
        $u = Get-DevModeSize $uBytes
        if (-not $u) { continue }
        $who = $hive.PSChildName
        try { $who = ((New-Object Security.Principal.SecurityIdentifier($who)).Translate([Security.Principal.NTAccount]).Value -split '\\')[-1] } catch {}
        $parts += "$who=$($u.Text)"
        if ($u.IsDefault) { $zebraAnyDefault = $true }
    }
    $zebraDetail += "$($zq.Name): $($parts -join ',')"
}

$zebra318 = @()
if ($logReadable -and $zebraQueues.Count -gt 0) {
    try {
        $zebra318 = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 318 } -MaxEvents 50 -ErrorAction Stop |
            Where-Object { "$($_.Message)" -match 'ZDesigner|Zebra' })
    } catch {
        if ($_.Exception.Message -notmatch 'No events were found') { Write-Log "Event query failed for $logName/318: $($_.Exception.Message)" }
    }
}
$zebraLast318 = if ($zebra318.Count -gt 0) { $zebra318[0].TimeCreated.ToString('yyyy-MM-dd HH:mm') } else { '-' }
$zebraRecent318 = @($zebra318 | Where-Object { $_.TimeCreated -ge (Get-Date).AddHours(-1 * $RecentResetHours) })
# Near HSS = within 15 min either side of the latest FULL apply (LastAppliedUtc is
# only written by ImportReport, never by a hash-match no-op run).
$zebra318NearHss = $false
if ($hssAppliedAt) {
    foreach ($e in $zebra318) { if ([math]::Abs(($e.TimeCreated - $hssAppliedAt).TotalMinutes) -le 15) { $zebra318NearHss = $true } }
}

if ($zebraQueues.Count -eq 0) { $zebraStatus = 'NO_ZEBRA' }
elseif ($zebraAnyDefault) { $zebraStatus = 'DEFAULT_SIZE' }
elseif ($zebraRecent318.Count -gt 0) { $zebraStatus = 'RESET_RECENT' }
elseif (@($zebraDetail | Where-Object { $_ -match 'defaults=\?' }).Count -gt 0) { $zebraStatus = 'UNKNOWN' }
else { $zebraStatus = 'OK' }
$zebraDetailText = if ($zebraDetail) { $zebraDetail -join '; ' } else { '-' }

# --- SUMMARY line (pipe-delimited; grep across SuperOps results) -------------
# Built from an array so no single physical line is long enough for the SuperOps
# editor to hard-wrap and corrupt.
$fields = @(
    "SUMMARY"
    "host=$env:COMPUTERNAME"
    "os=$caption"
    "winver=$display"
    "build=$build.$ubr"
    "status=$printBlockStatus"
    "log_readable=$logReadable"
    "wpp_policy=$wppPolicy"
    "wpp_local=$wppLocal"
    "wpp_eff=$wppEff"
    "wpp_on=$wppOn"
    "blocks=$blockCount"
    "current_blocks=$currentBlockCount"
    "historical_blocks=$historicalBlockCount"
    "current_since=$currentSinceText"
    "current_vendors=$currentVendorList"
    "current_codes=$currentCodeList"
    "current_dlls=$currentDllList"
    "historical_vendors=$vendorList"
    "historical_codes=$codeList"
    "historical_dlls=$dllList"
    "printers=$prnTotal"
    "not_normal=$prnBad"
    "hss_ran=$hssRan"
    "hss=$hssStatus"
    "hss_utc=$hssWhen"
    "hss_ver=$hssVer"
    "hss_exit=$hssExit"
    "hss_hash=$hssHash"
    "current_last_block=$currentLastBlock"
    "historical_last_block=$lastBlock"
    "zebra_settings=$zebraStatus"
    "zebra_last318=$zebraLast318"
    "zebra_318_near_hss=$zebra318NearHss"
    "zebra_detail=$zebraDetailText"
)
Write-Log ($fields -join '|')

# --- Human-readable detail ---------------------------------------------------
Write-Log ''
Write-Log "Host             : $env:COMPUTERNAME"
Write-Log "Windows          : $winVer"
Write-Log "WPP policy value : $wppPolicy   (Policies\...\Printers\WPP\WindowsProtectedPrintMode)"
Write-Log "WPP local value  : $wppLocal   EnabledBy=$wppEnby"
Write-Log "WPP effective    : $wppEff   -> Protected Print Mode $wppOnText"
Write-Log "Print block status: $printBlockStatus   (log readable: $logReadable)"
Write-Log "808 plug-in blocks: $blockCount total, $currentBlockCount current, $historicalBlockCount historical"
Write-Log "  current since  : $currentSinceText"
Write-Log "  current last   : $currentLastBlock"
Write-Log "  current vendors: $currentVendorList"
Write-Log "  current codes  : $currentCodeList   (0x679=CFG, 0x677=ACG/dynamic-code)"
Write-Log "  current DLLs   : $currentDllList"
Write-Log "  historic last  : $lastBlock"
Write-Log "  historic vendors: $vendorList"
Write-Log "  historic codes : $codeList"
Write-Log "  historic DLLs  : $dllList"
Write-Log "Printer queues   : $prnTotal total, $prnBad not-Normal"
Write-Log "  names          : $prnNames"
Write-Log "HSS has run here : $hssRan   (status=$hssStatus, exit=$hssExit, ver=$hssVer)"
Write-Log "  last applied   : $hssWhen   reportHash=$hssHash"
Write-Log "Zebra settings   : $zebraStatus   (last Zebra Event 318: $zebraLast318, near HSS full apply: $zebra318NearHss)"
Write-Log "  sizes (W x L mm): $zebraDetailText"
Write-Log "  DEFAULT_SIZE = saved settings are the 4x6in driver default; labels will"
Write-Log "  media-out on smaller stock. Signed-out users' preferences are not checked."
Write-Log ''
Write-Log "Dashboard status is current-only: BLOCKED_CURRENT / CLEAN / UNKNOWN."
Write-Log "If current_blocks>0 after HSS apply, investigate WPP, HSS report hash,"
Write-Log "and the named printer driver DLLs."
Write-Log "Historical blocks are retained as context only; PrintBlock_Status is current-only."
Write-Log ''

# --- Push to SuperOps custom fields (for fleet-wide reporting) ----------------
# Send-CustomField only exists inside the SuperOps script runtime; guard so the
# script still runs (and just skips this) when tested outside SuperOps.
# Supported data types: text, long text, decimal, number. Create these fields in
# the RMM Monitoring class first; rename the LEFT side here to match your fields.
$customFields = [ordered]@{
    'PrintBlock_Status'  = $printBlockStatus      # text  : BLOCKED_CURRENT / CLEAN / UNKNOWN
    'PrintBlock_Count'   = [int]$currentBlockCount # number: current # of 808 blocks after latest HSS apply/current window
    'PrintBlock_Total'   = [int]$blockCount       # number: optional historical context, total recent 808 plug-in blocks
    'PrintBlock_Vendors' = $currentVendorList     # text  : current Zebra,Brother,Star, or -
    'PrintBlock_Codes'   = $currentCodeList       # text  : current 0x679,0x677, or -
    'PrintBlock_LastUtc' = $currentLastBlock      # text  : most recent current block time, or blank
    'WPP_State'          = $wppOnText             # text  : ON / OFF
    'HSS_Ran'            = "$hssRan"              # text  : True / False
    'HSS_Status'         = $hssStatus             # text  : success / pending-install / -
    'HSS_LastUtc'        = $hssWhen               # text  : last HSS apply time
    'Win_BuildUBR'       = "$build.$ubr"          # text  : 26200.1234 (UBR pins the KB level;
                                                  #         OS / OS Version are already built-in)
    'ZebraSettings_Status'   = $zebraStatus        # text  : DEFAULT_SIZE / RESET_RECENT / OK / NO_ZEBRA / UNKNOWN
    'ZebraSettings_Last318'  = $zebraLast318       # text  : latest Zebra Event 318 time, or -
    'ZebraSettings_NearHss'  = "$zebra318NearHss"  # text  : True if a Zebra 318 was within 15 min of the last HSS full apply
    'ZebraSettings_Detail'   = $zebraDetailText    # long text: per-queue defaults + per-user sizes in mm
}
if (Get-Command Send-CustomField -ErrorAction SilentlyContinue) {
    foreach ($f in $customFields.GetEnumerator()) {
        try {
            Send-CustomField -CustomFieldName $f.Key -Value $f.Value
            Write-Log "CustomField set: $($f.Key) = $($f.Value)"
        } catch {
            Write-Log "CustomField FAILED: $($f.Key) - $_"
        }
    }
} else {
    $hint = if ($SuperOpsModule) { '$SuperOpsModule set but Import-Module failed' }
            else { '$SuperOpsModule not set - not running under SuperOps, or module not injected' }
    Write-Log "Send-CustomField not available ($hint) - custom fields skipped."
}

Write-Log ''
Write-Log "Transcript: $transcript"
