<#
.SYNOPSIS
    STEP 4 of the Zebra end-to-end test. Restores the printers (queues + drivers
    + ports + tray/duplex settings) that the Step 3 full apply wiped, from the
    Step 2 PrintBrm backup - and watches whether they come back, with configs,
    and whether the hardened spooler immediately re-blocks them.

.DESCRIPTION
    Recovery + learning step:
      1. Finds the newest PrinterBackup-<host>-*.printerExport (Step 2).
      2. Pre-snapshot of current queues + 808 high-water.
      3. Restores with PrintBrm  -R -F <file> -O FORCE  (overwrite existing).
      4. Re-snapshots: which queues returned (Zebra/Brother flagged), their
         status, and their restored tray/duplex config (Get-PrintConfiguration).
      5. Reports any NEW 808 blocks the restore itself triggered - i.e. whether
         the now-hardened spooler re-rejects the same legacy plug-ins.

    IMPORTANT: this restores the SAME legacy drivers. It is a RECOVERY tool, not
    the durable fix. Restored legacy-driver queues may print now but can be
    knocked again on the next spooler restart / next report change. The durable
    fix (driverless / IPP for network printers; a separate plan for USB Zebra)
    is designed AFTER this.

    After it runs: physically PRINT a Zebra label and a Brother test page and
    report whether they actually print.

    Console + transcript at C:\Temp.

.NOTES
    SuperOps (SYSTEM) or elevated admin PowerShell on the box. Self-contained.
    PS 5.1-safe. No automated tests. Part of the Test-ZebraApply-*.ps1 kit.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "ZebraTest-4-Restore-$env:COMPUTERNAME.log"
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

$vendorRegex = 'Epson|Zebra|ZDesigner|ZDN|Brother|BRU|Star|TSP|TM-'
$zebraRegex  = 'Zebra|ZDesigner|ZDN'
$log808      = 'Microsoft-Windows-PrintService/Admin'

Write-Log "Zebra end-to-end test - STEP 4 RESTORE (recover printers + trays)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. Locate the backup
# -----------------------------------------------------------------------------
Write-Section '1. Locate Step 2 backup'
$backup = $null
foreach ($dir in 'C:\Install','C:\Temp') {
    $cand = Get-ChildItem -LiteralPath $dir -Filter "PrinterBackup-$env:COMPUTERNAME-*.printerExport" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $backup = $cand; break }
}
if (-not $backup) {
    Write-Log "ABORT: no PrinterBackup-$env:COMPUTERNAME-*.printerExport found. Nothing to restore from."
    return
}
Write-Log "Restoring from: $($backup.FullName)  ($([math]::Round($backup.Length/1KB,1)) KB)"

# -----------------------------------------------------------------------------
# 2. Pre-snapshot
# -----------------------------------------------------------------------------
Write-Section '2. PRE-restore snapshot'
function Get-PrinterSnapshot {
    try { return Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus }
    catch { Write-Log "  (Get-Printer failed: $_)"; return @() }
}
$prePrinters = @(Get-PrinterSnapshot)
Write-Block $prePrinters 'Table'
$restoreStart = Get-Date
Write-Log ''
Write-Log "Restore start marker: $($restoreStart.ToString('HH:mm:ss')) (any 808 after this is from the restore)"

# -----------------------------------------------------------------------------
# 3. Restore
# -----------------------------------------------------------------------------
Write-Section '3. PrintBrm restore (-R -F <file> -O FORCE)'
$brm = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'
if (-not (Test-Path -LiteralPath $brm)) {
    Write-Log "ABORT: PrintBrm.exe not found at $brm"
    return
}
Write-Log "Running: $brm -R -F `"$($backup.FullName)`" -O FORCE"
try {
    & $brm -R -F $backup.FullName -O FORCE *>> $transcript
    Write-Log "PrintBrm restore exit code: $LASTEXITCODE"
} catch { Write-Log "ERROR running PrintBrm restore: $_" }

# -----------------------------------------------------------------------------
# 4. POST-restore snapshot + tray config
# -----------------------------------------------------------------------------
Write-Section '4. POST-restore snapshot'
$postPrinters = @()
for ($i=0; $i -lt 6; $i++) {
    $postPrinters = @(Get-PrinterSnapshot)
    if ($postPrinters.Count -gt 1) { break }
    Start-Sleep -Seconds 5
}
Write-Block $postPrinters 'Table'

$preNames  = @($prePrinters  | ForEach-Object { $_.Name })
$postNames = @($postPrinters | ForEach-Object { $_.Name })
$recovered = @($postNames | Where-Object { $_ -notin $preNames })
Write-Log ''
Write-Log "Queues recovered by restore: $($recovered.Count)"
foreach ($r in $recovered) {
    $mark = if ($r -match $zebraRegex) { '  <<< ZEBRA' } elseif ($r -match $vendorRegex) { '  <<< vendor' } else { '' }
    Write-Log "  + $r$mark"
}

Write-Section '4b. Restored tray / duplex config (proof configs came back)'
foreach ($p in $postPrinters) {
    if ($p.Name -notmatch $vendorRegex) { continue }
    try {
        $cfg = Get-PrintConfiguration -PrinterName $p.Name -ErrorAction Stop
        Write-Log "  $($p.Name): Paper=$($cfg.PaperSize)  Duplex=$($cfg.DuplexingMode)  Color=$($cfg.Color)"
    } catch { Write-Log "  $($p.Name): (Get-PrintConfiguration failed: $_)" }
}

# -----------------------------------------------------------------------------
# 5. Did the restore re-trigger 808 blocks (hardened spooler re-rejecting)?
# -----------------------------------------------------------------------------
Write-Section '5. NEW 808 blocks since restore start (does hardening re-reject?)'
$new = @()
try {
    $new = Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808; StartTime=$restoreStart } -ErrorAction SilentlyContinue | Sort-Object TimeCreated
} catch { }
if (-not $new -or $new.Count -eq 0) {
    Write-Log "  NONE so far - restored queues loaded without an immediate plug-in block."
    Write-Log "  (The real durability test is the NEXT spooler restart / reboot.)"
} else {
    foreach ($e in $new) {
        $mm  = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        $cm  = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
        $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
        $code= if ($cm.Success) { $cm.Value } else { '?' }
        $flag= if ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex) { '  <<< ZEBRA' }
               elseif ("$($e.Message)" -match $vendorRegex) { '  <<< vendor' } else { '' }
        Write-Log ("  {0}  {1,-22} code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code, $flag)
    }
    Write-Log ''
    Write-Log "  Blocks fired on restore -> the hardened spooler still rejects these plug-ins."
    Write-Log "  Restored legacy queues may show up but still fail to print. Confirm physically."
}

# -----------------------------------------------------------------------------
# 6. Next actions
# -----------------------------------------------------------------------------
Write-Section '6. VERDICT + next actions'
$zebraBack = [bool](@($postPrinters | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex }))
Write-Log "Zebra queue restored : $zebraBack"
Write-Log ''
Write-Log "NOW DO THIS:"
Write-Log "  1. Physically PRINT A ZEBRA LABEL and a BROTHER test page."
Write-Log "  2. Tell me whether each actually prints."
Write-Log ''
Write-Log "Remember: this restored the SAME legacy drivers. If they print now, they can still"
Write-Log "be knocked again on the next reboot / next HSS report change. The durable fix"
Write-Log "(driverless IPP for the network Brothers; a separate plan for the USB Zebra) is the"
Write-Log "next thing we design - this step was to recover the box and learn the recovery path."

Write-Section 'Step 4 complete'
Write-Log "Transcript: $transcript"
