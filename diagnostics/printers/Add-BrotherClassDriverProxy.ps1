<#
.SYNOPSIS
    Proxy test (part 1 of 2): create a NEW Brother queue on a Standard TCP/IP
    port using a Microsoft inbox CLASS driver (Microsoft-signed, CFG-clean), so
    we can test whether it survives a full HSS apply while the existing
    WSD + vendor-driver Brother queues vanish.

    Part 2 = run Test-ZebraApply-3-TriggerAndWatch.ps1 (force-full + watch + diff)
    and confirm 'Brother-CLASS-TEST' is NOT in the vanished list.

.DESCRIPTION
    1. Shows the current Brother queues + their ports (controls).
    2. Prompts for the Brother's IP (or set $BrotherIP below).
    3. Creates a Standard TCP/IP (RAW 9100) port to that IP.
    4. Adds the queue 'Brother-CLASS-TEST' with the Microsoft IPP Class Driver
       (best - earns the green 'protected' shield) and, if that can't print,
       you can re-run choosing the PCL6 class driver fallback.
    5. Leaves the existing WSD/vendor Brother queues untouched as controls.

    After it runs: PRINT A TEST PAGE to 'Brother-CLASS-TEST'. If it prints, run
    the full-apply survival test (Step 3) and check it survives.

.NOTES
    Elevated admin PowerShell on the box. PS 5.1-safe. Self-contained.
    Makes additive changes only (one new port + one new queue); does not modify
    or remove the existing Brother queues.
#>

param(
    [string]$BrotherIP = '',                       # set this, or you'll be prompted
    [string]$DriverName = 'Microsoft IPP Class Driver',  # fallback: 'Microsoft PCL6 Class Driver'
    [string]$QueueName = 'Brother-CLASS-TEST'
)

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "BrotherClassProxy-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block { param($o) if($null -eq $o){Write-Log '  (none)';return}; foreach($l in (($o|Format-Table -AutoSize|Out-String -Width 4096) -split "`r?`n")){ if($l.TrimEnd()){Write-Log $l.TrimEnd()} } }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

Write-Log "Brother class-driver PROXY (part 1: create TCP/IP + class-driver queue)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# -----------------------------------------------------------------------------
# 1. Show current Brother queues + ports (controls)
# -----------------------------------------------------------------------------
Write-Section '1. Current Brother queues + ports (these stay as CONTROLS)'
$allPrinters = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object Name,DriverName,PortName,PrinterStatus)
$brothers = @($allPrinters | Where-Object { $_.Name -match 'Brother|BRN|BRW' -or $_.DriverName -match 'Brother' })
Write-Block $brothers
Write-Log ''
Write-Log "WSD/vendor Brother ports (for reference - cannot read an IP directly from WSD):"
try { Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'WSD' -or $_.Name -match 'Brother' } | Select-Object Name,Description,PrinterHostAddress | Format-Table -AutoSize | Out-String -Width 4096 | ForEach-Object { foreach($l in ($_ -split "`r?`n")){ if($l.TrimEnd()){Write-Log $l.TrimEnd()} } } } catch {}

# -----------------------------------------------------------------------------
# 2. Get the Brother IP
# -----------------------------------------------------------------------------
Write-Section '2. Brother IP'
if ([string]::IsNullOrWhiteSpace($BrotherIP)) {
    Write-Log "No IP supplied. Get it from the printer panel (Network) or your router DHCP list."
    $BrotherIP = Read-Host "Enter the Brother printer's IP address"
}
$BrotherIP = $BrotherIP.Trim()
if ($BrotherIP -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    Write-Log "ABORT: '$BrotherIP' is not a valid IPv4 address."
    return
}
Write-Log "Using Brother IP: $BrotherIP"
Write-Log "Pinging to confirm reachable..."
if (Test-Connection -ComputerName $BrotherIP -Count 2 -Quiet -ErrorAction SilentlyContinue) {
    Write-Log "  reachable."
} else {
    Write-Log "  WARNING: no ping reply. Continuing anyway (printer may block ICMP), but check the IP if printing fails."
}

# -----------------------------------------------------------------------------
# 3. Create the Standard TCP/IP port (RAW 9100)
# -----------------------------------------------------------------------------
Write-Section '3. Standard TCP/IP port (RAW 9100)'
$portName = "IP_$BrotherIP"
try {
    if (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
        Write-Log "  port $portName already exists - reusing."
    } else {
        Add-PrinterPort -Name $portName -PrinterHostAddress $BrotherIP -ErrorAction Stop
        Write-Log "  created port $portName -> $BrotherIP (RAW 9100)"
    }
} catch { Write-Log "  ERROR creating port: $_"; return }

# -----------------------------------------------------------------------------
# 4. Ensure the class driver is available, then create the queue
# -----------------------------------------------------------------------------
Write-Section "4. Create queue '$QueueName' with '$DriverName'"
# Make sure the inbox class driver is staged.
$haveDriver = $false
try { if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) { $haveDriver = $true } } catch {}
if (-not $haveDriver) {
    Write-Log "  driver '$DriverName' not staged yet - adding from the inbox driver store..."
    try { Add-PrinterDriver -Name $DriverName -ErrorAction Stop; $haveDriver = $true; Write-Log "  added '$DriverName'." }
    catch { Write-Log "  ERROR: could not add '$DriverName': $_" }
}
if (-not $haveDriver) {
    Write-Log "  Try re-running with: -DriverName 'Microsoft PCL6 Class Driver'"
    Write-Log "  Available class drivers on this box:"
    try { Get-PrinterDriver | Where-Object { $_.Name -match 'Microsoft (IPP|PCL|PS|XPS).*Class' -or $_.Manufacturer -eq 'Microsoft' } | Select-Object Name | Format-Table -AutoSize | Out-String -Width 4096 | ForEach-Object { foreach($l in ($_ -split "`r?`n")){ if($l.TrimEnd()){Write-Log $l.TrimEnd()} } } } catch {}
    return
}

try {
    if (Get-Printer -Name $QueueName -ErrorAction SilentlyContinue) {
        Write-Log "  queue '$QueueName' already exists - removing and recreating."
        Remove-Printer -Name $QueueName -ErrorAction SilentlyContinue
    }
    Add-Printer -Name $QueueName -DriverName $DriverName -PortName $portName -ErrorAction Stop
    Write-Log "  created queue '$QueueName' [$DriverName] on $portName"
} catch { Write-Log "  ERROR creating queue: $_"; return }

# -----------------------------------------------------------------------------
# 5. Report + next step
# -----------------------------------------------------------------------------
Write-Section '5. Result'
$now = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object Name,DriverName,PortName,PrinterStatus)
Write-Block ($now | Where-Object { $_.Name -eq $QueueName -or $_.Name -match 'Brother|BRN|BRW' -or $_.DriverName -match 'Brother' })
Write-Log ''
Write-Log "NEXT:"
Write-Log "  1. In Settings > Printers, check if '$QueueName' shows the GREEN protected-mode shield."
Write-Log "  2. PRINT A TEST PAGE to '$QueueName' and confirm it physically prints."
Write-Log "       (Settings > $QueueName > Printer properties > Print Test Page, or:"
Write-Log "        rundll32 printui.dll,PrintUIEntry /k /n `"$QueueName`" )"
Write-Log "  3. If it prints: run Test-ZebraApply-3-TriggerAndWatch.ps1 (force-full apply +"
Write-Log "     watch) and confirm '$QueueName' is NOT in the vanished list while the WSD"
Write-Log "     Brother queues ARE. That proves the class-driver + TCP/IP fix survives hardening."
Write-Log "  4. If it does NOT print: re-run this with -DriverName 'Microsoft PCL6 Class Driver'."
Write-Log ''
Write-Log "Transcript: $transcript"
