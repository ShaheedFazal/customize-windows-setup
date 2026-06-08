<#
.SYNOPSIS
    Compact, read-only FLEET sweep for the print-stack hardening that blocks legacy
    (non-CFG / non-ACG) third-party printer driver plug-ins - Zebra (ZDesigner),
    Brother (BRU*), Star (star*/tsp*), etc. Push fleet-wide via SuperOps to find the
    pattern: which machines are blocked, and does it correlate with Windows Protected
    Print Mode (WPP) state, OS build, or HSS apply state?

.DESCRIPTION
    Emits ONE pipe-delimited SUMMARY line per endpoint (easy to eyeball / aggregate
    across many SuperOps results), then a short human-readable detail block. Reports:
      - OS build
      - WPP policy + effective state  (the usual trigger for CFG/ACG plug-in blocks)
      - PrintService/Admin Event 808 plug-in-load blocks: count, distinct DLLs,
        distinct error codes, most recent timestamp
      - printer queues: total + how many are NOT in Normal state
      - HSS apply state (did our baseline run here, and when)

    Read-only: no registry/driver/printer/service/policy changes.

.NOTES
    SuperOps (SYSTEM). Self-contained. No automated tests (AGENTS.md).
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "PrinterCFGSweep-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

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
# Distinguish three states: BLOCKED (>0), CLEAN (log readable, 0 events), and
# UNKNOWN (log disabled / unreadable - so a blank dashboard cell isn't mistaken
# for "genuinely clean"). We check the log is enabled FIRST (-ListLog), then use
# SilentlyContinue for the query so the benign "no events match" case returns
# $null instead of a locale-dependent terminating error.
$blockCount = 0; $dlls = @(); $codes = @(); $lastBlock = ''
$logName     = 'Microsoft-Windows-PrintService/Admin'
$logReadable = $false
try {
    $logInfo = Get-WinEvent -ListLog $logName -ErrorAction Stop
    if ($logInfo.IsEnabled) { $logReadable = $true }
} catch { $logReadable = $false }

if ($logReadable) {
    $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 808 } `
        -MaxEvents 200 -ErrorAction SilentlyContinue
    if ($events) {
        $blockCount = @($events).Count
        $lastBlock  = $events[0].TimeCreated.ToString('yyyy-MM-dd HH:mm')
        foreach ($e in $events) {
            $ud = ''
            try { $ud = ([xml]$e.ToXml()).Event.UserData.InnerXml } catch {}
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
if ($dllList -match 'ZDesigner') { $vendors += 'Zebra' }
if ($dllList -match 'BRU|brother|broh') { $vendors += 'Brother' }
if ($dllList -match 'star|tsp|tup') { $vendors += 'Star' }
$vendorList = if ($vendors) { ($vendors | Sort-Object -Unique) -join ',' } else { '-' }

# Three-state status: BLOCKED / CLEAN / UNKNOWN (log disabled or unreadable).
$printBlockStatus =
    if (-not $logReadable) { 'UNKNOWN' }
    elseif ($blockCount -gt 0) { 'BLOCKED' }
    else { 'CLEAN' }

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
# Apply-HSS scheduled task (see Ensure-Apps.ps1). This lets us correlate
# "blocked" vs "HSS has run here" across branches - the whole point of the sweep.
$hssStatus = '-'; $hssWhen = '-'; $hssHash = '-'; $hssVer = '-'; $hssExit = '-'
$hssKey = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$s = Get-RegVal $hssKey 'LastAppliedStatus';   if ($s) { $hssStatus = $s }
$w = Get-RegVal $hssKey 'LastAppliedUtc';      if ($w) { $hssWhen   = $w }
$h = Get-RegVal $hssKey 'ReportHash';          if ($h) { $hssHash   = ($h.Substring(0, [Math]::Min(12, $h.Length))) }
$v = Get-RegVal $hssKey 'AppliedHssVersion';   if ($v) { $hssVer    = $v }
$x = Get-RegVal $hssKey 'LastAppliedExitCode'; if ($null -ne $x) { $hssExit = $x }
# 'hss_ran' is the clean yes/no: did the apply task ever record a state here?
$hssRan = (Test-Path $hssKey) -and ($hssStatus -ne '-')

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
    "vendors=$vendorList"
    "codes=$codeList"
    "dlls=$dllList"
    "printers=$prnTotal"
    "not_normal=$prnBad"
    "hss_ran=$hssRan"
    "hss=$hssStatus"
    "hss_utc=$hssWhen"
    "hss_ver=$hssVer"
    "hss_exit=$hssExit"
    "hss_hash=$hssHash"
    "last_block=$lastBlock"
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
Write-Log "808 plug-in blocks: $blockCount   last: $lastBlock"
Write-Log "  vendors        : $vendorList"
Write-Log "  error codes    : $codeList   (0x679=CFG, 0x677=ACG/dynamic-code)"
Write-Log "  blocked DLLs   : $dllList"
Write-Log "Printer queues   : $prnTotal total, $prnBad not-Normal"
Write-Log "  names          : $prnNames"
Write-Log "HSS has run here : $hssRan   (status=$hssStatus, exit=$hssExit, ver=$hssVer)"
Write-Log "  last applied   : $hssWhen   reportHash=$hssHash"
Write-Log ''
Write-Log "Correlation to check across branches: does blocks>0 line up with hss_ran=True?"
Write-Log "If unhardened machines (hss_ran=False) are clean and hardened ones are blocked,"
Write-Log "the hardening stack is implicated even though WPP/mitigations read as off."
Write-Log ''

# --- Push to SuperOps custom fields (for fleet-wide reporting) ----------------
# Send-CustomField only exists inside the SuperOps script runtime; guard so the
# script still runs (and just skips this) when tested outside SuperOps.
# Supported data types: text, long text, decimal, number. Create these fields in
# the RMM Monitoring class first; rename the LEFT side here to match your fields.
$customFields = [ordered]@{
    'PrintBlock_Status'  = $printBlockStatus      # text  : BLOCKED / CLEAN  (primary filter)
    'PrintBlock_Count'   = [int]$blockCount       # number: # of 808 plug-in blocks
    'PrintBlock_Vendors' = $vendorList            # text  : Zebra,Brother,Star
    'PrintBlock_Codes'   = $codeList              # text  : 0x679,0x677
    'PrintBlock_LastUtc' = $lastBlock             # text  : most recent block time
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
    Write-Log "Send-CustomField not available (not running under SuperOps) - skipped."
}

Write-Log ''
Write-Log "Transcript: $transcript"
