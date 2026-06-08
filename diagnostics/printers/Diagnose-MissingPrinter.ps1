<#
.SYNOPSIS
    Read-only diagnostic for a printer that has DISAPPEARED from Printers &
    Scanners (e.g. Epson not showing) - a different symptom from the Event 808
    plug-in block. Run on the affected box (e.g. PC2-FQ688).

.DESCRIPTION
    "Vanished queue" vs "plug-in load error" are different problems. This script
    answers, for every printer and especially Epson:
      - Is the queue still present (Get-Printer) and is it offline/error?
      - Is the driver still installed (Get-PrinterDriver)?
      - Is the port still there (Get-PrinterPort) - USB vs TCP/IP?
      - Is the physical device present in PnP, and is it healthy or errored?
        (catches a USB receipt printer that's unplugged / driver not bound)
      - When was a printer/queue ADDED or REMOVED? (PrintService/Operational
        300/301/302, Admin, + spooler events) - so we can see when Epson left
        and whether it lines up with a boot, an update, or the HSS apply.
      - Any 808 plug-in blocks naming Epson modules (E_*.dll / ESCPR / EPSON).

    Vendors flagged: Epson, Zebra, Brother, Star.

    ONLY READS. No changes. Console + transcript.

.NOTES
    SuperOps (SYSTEM). Self-contained. PS 5.1-safe. No automated tests.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "MissingPrinter-$env:COMPUTERNAME.log"
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

$vendorRegex = 'Epson|Zebra|ZDesigner|Brother|BRU|Star|TSP|TM-'

Write-Log "Missing-printer diagnostic"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. All printer QUEUES - present? offline? (Get-Printer + WMI WorkOffline)
# -----------------------------------------------------------------------------
Write-Section '1. Printer queues (Get-Printer + offline state)'
try {
    Write-Block (Get-Printer -ErrorAction Stop |
        Select-Object Name, DriverName, PortName, Shared, Published, PrinterStatus) 'Table'
} catch { Write-Log "ERROR Get-Printer: $_" }

Write-Log ''
Write-Log "-- Win32_Printer (WorkOffline / status) --"
try {
    Write-Block (Get-CimInstance Win32_Printer -ErrorAction Stop |
        Select-Object Name, WorkOffline, PrinterStatus, PortName, Default) 'Table'
} catch { Write-Log "ERROR Win32_Printer: $_" }

# -----------------------------------------------------------------------------
# 2. All printer DRIVERS - is the Epson driver still installed?
# -----------------------------------------------------------------------------
Write-Section '2. Printer drivers (Epson/Zebra/Brother/Star flagged)'
try {
    $drivers = Get-PrinterDriver -ErrorAction Stop | ForEach-Object {
        $flag = ''
        if ($_.Name -match $vendorRegex -or $_.Manufacturer -match $vendorRegex) { $flag = '<<<' }
        [pscustomobject]@{ Flag=$flag; Name=$_.Name; Manufacturer=$_.Manufacturer }
    }
    Write-Block $drivers 'Table'
} catch { Write-Log "ERROR Get-PrinterDriver: $_" }

# -----------------------------------------------------------------------------
# 3. Printer PORTS - is the Epson port (USB / TCPIP) still there?
# -----------------------------------------------------------------------------
Write-Section '3. Printer ports'
try {
    Write-Block (Get-PrinterPort -ErrorAction Stop |
        Select-Object Name, Description, PrinterHostAddress, PortNumber) 'Table'
} catch { Write-Log "ERROR Get-PrinterPort: $_" }

# -----------------------------------------------------------------------------
# 4. PnP devices - is the physical Epson present and healthy?
#    Catches a USB printer that's unplugged / powered off / driver not bound.
# -----------------------------------------------------------------------------
Write-Section '4. PnP devices (printers + anything Epson/Zebra/Brother/Star)'
try {
    $pnp = Get-PnpDevice -ErrorAction Stop | Where-Object {
        $_.Class -in 'Printer','PrintQueue','Image','USB' -or $_.FriendlyName -match $vendorRegex
    } | Where-Object { $_.FriendlyName -match $vendorRegex -or $_.Class -in 'Printer','PrintQueue' } |
        Select-Object Status, Class, FriendlyName, InstanceId
    if ($pnp) { Write-Block $pnp 'Table' } else { Write-Log '  (no matching PnP devices)' }
    Write-Log ''
    Write-Log "Status meanings: OK = present/healthy, Error = present but problem,"
    Write-Log "Unknown/Degraded = driver issue, (absent entirely) = not connected."
} catch { Write-Log "ERROR Get-PnpDevice: $_" }

# -----------------------------------------------------------------------------
# 5. Printer ADD / REMOVE history - when did a queue appear or vanish?
# -----------------------------------------------------------------------------
Write-Section '5. Printer add/remove history (last 30 days)'
$since = (Get-Date).AddDays(-30)
foreach ($pair in @(
    @('Microsoft-Windows-PrintService/Operational', @(300,301,302,306,307)),
    @('Microsoft-Windows-PrintService/Admin',       @(808,812,815,816))
)) {
    $ln = $pair[0]; $ids = $pair[1]
    Write-Log "[$ln  Ids: $($ids -join ',')]"
    try {
        $evs = Get-WinEvent -FilterHashtable @{ LogName=$ln; Id=$ids; StartTime=$since } -ErrorAction Stop |
            Select-Object -First 60
        if ($evs) {
            foreach ($e in $evs) {
                $msg = ($e.Message -split "`r?`n")[0]
                $mark = if ($msg -match $vendorRegex) { ' <<<' } else { '' }
                Write-Log ("  {0}  Id={1,-4} {2}{3}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.Id, $msg, $mark)
            }
        } else { Write-Log '  (no events / log empty)' }
    } catch { Write-Log "  (no events or log disabled: $_)" }
}

# -----------------------------------------------------------------------------
# 6. Spooler / driver System events naming the vendors (last 30 days)
# -----------------------------------------------------------------------------
Write-Section '6. System log spooler/driver events naming the vendors'
try {
    $sys = Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=$since } -ErrorAction Stop |
        Where-Object { $_.Message -match $vendorRegex } | Select-Object -First 40
    if ($sys) {
        foreach ($s in $sys) {
            $msg = ($s.Message -split "`r?`n")[0]
            Write-Log ("  {0}  [{1}] Id={2}  {3}" -f $s.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $s.ProviderName, $s.Id, $msg)
        }
    } else { Write-Log '  (none naming Epson/Zebra/Brother/Star)' }
} catch { Write-Log "  ERROR: $_" }

Write-Section 'Diagnostic complete (read-only - no changes made)'
Write-Log "Transcript: $transcript"
