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
