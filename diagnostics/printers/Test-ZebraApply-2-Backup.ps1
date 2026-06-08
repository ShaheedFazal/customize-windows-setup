<#
.SYNOPSIS
    STEP 2 of the Zebra end-to-end test. Backs up EVERY printer + driver + port
    + per-printer settings (trays/duplex) so the destructive Step 3 has a real
    safety net, and so we can prove backup->restore brings tray configs back.

.DESCRIPTION
    Two outputs:
      1. PrintBrm (Printer Migration) binary export - the canonical Windows
         printer backup. Captures queues, drivers, ports AND each printer's
         DEVMODE (default tray, duplex, paper). This is what Step 4 restores.
            C:\Temp\PrinterBackup-<host>-<stamp>.printerExport
            C:\Install\PrinterBackup-<host>-<stamp>.printerExport   (copy)
      2. A human-readable inventory (.txt) - Get-Printer / Get-PrinterDriver /
         Get-PrinterPort + Get-PrintConfiguration per printer (paper/duplex),
         so even without restoring you have a written record of the settings.

    This script makes NO changes to printers - it only reads and exports.

    NOTE: PrintBrm export does not block; if it reports 0 printers, check that
    the spooler is running. The binary export is the authoritative restore
    source - the .txt is a convenience record.

.NOTES
    SuperOps (SYSTEM). Self-contained. PS 5.1-safe. No automated tests.
    Part of the Test-ZebraApply-*.ps1 kit (1 baseline, 2 backup,
    3 trigger+watch, 4 restore).
#>

$ErrorActionPreference = 'Continue'

$logDir     = 'C:\Temp'
$installDir = 'C:\Install'
foreach ($d in $logDir, $installDir) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "ZebraTest-2-Backup-$env:COMPUTERNAME.log"
$exportName = "PrinterBackup-$env:COMPUTERNAME-$stamp.printerExport"
$exportTemp = Join-Path $logDir $exportName
$exportSafe = Join-Path $installDir $exportName
$inventory  = Join-Path $installDir "PrinterInventory-$env:COMPUTERNAME-$stamp.txt"

function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Inv { param([string]$m) try { Add-Content -LiteralPath $inventory -Value $m -Encoding UTF8 } catch {} }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

Write-Log "Zebra end-to-end test - STEP 2 backup (printer export, no changes)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. Human-readable inventory (written first, so we have it even if PrintBrm chokes)
# -----------------------------------------------------------------------------
Write-Section '1. Human-readable inventory (.txt record of trays/duplex/ports)'
Inv "Printer inventory for $env:COMPUTERNAME  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Inv ('=' * 70)

try {
    $printers = Get-Printer -ErrorAction Stop
    foreach ($p in $printers) {
        Inv ''
        Inv "PRINTER: $($p.Name)"
        Inv "  Driver : $($p.DriverName)"
        Inv "  Port   : $($p.PortName)"
        Inv "  Shared : $($p.Shared)   Status: $($p.PrinterStatus)"
        try {
            $cfg = Get-PrintConfiguration -PrinterName $p.Name -ErrorAction Stop
            Inv "  Config : PaperSize=$($cfg.PaperSize)  Duplex=$($cfg.DuplexingMode)  Color=$($cfg.Color)  Collate=$($cfg.Collate)"
        } catch { Inv "  Config : (Get-PrintConfiguration failed: $_)" }
    }
    Write-Log "  Inventoried $($printers.Count) printer(s) -> $inventory"
} catch { Write-Log "  ERROR enumerating printers: $_"; Inv "ERROR enumerating printers: $_" }

# Append driver + port lists to the inventory for completeness.
Inv ''; Inv ('=' * 70); Inv 'DRIVERS'
try { Get-PrinterDriver | ForEach-Object { Inv "  $($_.Name)  [$($_.Manufacturer)]" } } catch { Inv "  ERROR: $_" }
Inv ''; Inv ('=' * 70); Inv 'PORTS'
try { Get-PrinterPort | ForEach-Object { Inv "  $($_.Name)  $($_.Description)  $($_.PrinterHostAddress)" } } catch { Inv "  ERROR: $_" }
Write-Log "  Inventory written: $inventory"

# -----------------------------------------------------------------------------
# 2. PrintBrm binary export - the authoritative restore source
# -----------------------------------------------------------------------------
Write-Section '2. PrintBrm export (the file Step 4 restores from)'
$brm = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'
if (-not (Test-Path -LiteralPath $brm)) {
    Write-Log "  ERROR: PrintBrm.exe not found at $brm"
    Write-Log "  Cannot produce a binary backup. The .txt inventory above is still written."
} else {
    Write-Log "  PrintBrm   : $brm"
    Write-Log "  Exporting all printers/drivers/ports/settings to:"
    Write-Log "    $exportTemp"
    try {
        & $brm -B -F $exportTemp *>> $transcript
        $code = $LASTEXITCODE
        Write-Log "  PrintBrm exit code: $code"
    } catch { Write-Log "  ERROR running PrintBrm: $_" }

    if (Test-Path -LiteralPath $exportTemp) {
        $sz = (Get-Item -LiteralPath $exportTemp).Length
        Write-Log "  Export file created: $exportTemp  ($([math]::Round($sz/1KB,1)) KB)"
        if ($sz -gt 0) {
            try {
                Copy-Item -LiteralPath $exportTemp -Destination $exportSafe -Force
                Write-Log "  Safe copy        : $exportSafe"
            } catch { Write-Log "  WARNING: could not copy to $installDir : $_" }
        } else {
            Write-Log "  WARNING: export file is 0 bytes - backup is NOT valid. Check spooler."
        }
    } else {
        Write-Log "  ERROR: export file was not created. Backup FAILED - do NOT proceed to Step 3."
    }
}

# -----------------------------------------------------------------------------
# 3. Summary / go-no-go for Step 3
# -----------------------------------------------------------------------------
Write-Section '3. Backup summary'
$haveBinary = (Test-Path -LiteralPath $exportSafe) -and ((Get-Item -LiteralPath $exportSafe -ErrorAction SilentlyContinue).Length -gt 0)
$haveInv    = Test-Path -LiteralPath $inventory
Write-Log "Binary backup (restorable): $haveBinary"
Write-Log "  -> $exportSafe"
Write-Log "Text inventory            : $haveInv"
Write-Log "  -> $inventory"
Write-Log ''
if ($haveBinary) {
    Write-Log "READ: safety net is in place. Safe to run Step 3 (trigger + watch the break)."
    Write-Log "      If anything is lost, Step 4 restores from the binary backup above."
} else {
    Write-Log "READ: NO valid binary backup - do NOT run Step 3 yet. Fix the export first"
    Write-Log "      (spooler running? PrintBrm present?) so we have a real safety net."
}

Write-Section 'Backup complete (no printer changes made)'
Write-Log "Transcript: $transcript"
