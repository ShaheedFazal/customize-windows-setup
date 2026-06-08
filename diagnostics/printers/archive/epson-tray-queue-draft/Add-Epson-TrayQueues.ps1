# Creates the dual logical print queues ("A4" and "Token") for the Epson
# WF-C579R dispensing printer used by Titan PMR, and locks in each queue's
# tray / paper-size / colour defaults from captured DEVMODE blobs.
#
# WHY TWO QUEUES: Titan PMR selects output by Windows printer name. One
# physical WF-C579R is exposed as two queues so Titan can route A4 documents
# (picking lists, grayscale, Cassette 1) and prescription Tokens (custom
# 211x177mm size, Cassette 2) to the same device on different trays. The
# default "EPSON WF-C579R Series" queue created at install is removed once A4
# and Token exist, so users and Titan only ever see the two logical queues.
# See the "Configuring Epson WF-C579 Printer with Titan" runbook for the
# manual steps this script automates.
#
# SCOPE / SAFETY: This is a no-op on every machine that does NOT already have
# a WF-C579R driver+queue installed, so it is safe in the estate-wide include
# chain - sites without the Epson are left untouched. A technician still
# installs the printer once by hand (driver + TCP/IP port); this script then
# guarantees the A4/Token queues and their tray defaults exist and are
# correct. That also means it self-heals: if a spooler restart ever drops the
# logical queues, the next customize run recreates them (note: it cannot
# recover from driver loss - see printer-cfg-block root cause).
#
# TRAY DEFAULTS: The Epson driver stores tray / custom-size / grayscale in its
# private DEVMODE, which PowerShell's Set-PrintConfiguration cannot reach. We
# instead replay a per-queue settings blob captured once with
# `printui.dll /Ss` on a reference machine. See printer-configs\README.md for
# how to (re)capture A4.dat and Token.dat. If a blob is missing, the queue is
# still created and logged - the tech just sets that tray by hand once.

if (Test-MachineWideSentinel -Name 'Add-Epson-TrayQueues') { return }

# Match the model loosely so a driver-name revision (e.g. "EPSON WF-C579R
# Series") still resolves.
$ModelMatch = '*WF-C579R*'
$ConfigDir  = Join-Path $PSScriptRoot 'printer-configs'

# Queue name -> captured DEVMODE blob. Queue names are exact: Titan PMR's
# print profiles reference "A4" and "Token" verbatim.
$Queues = @(
    @{ Name = 'A4';    Dat = 'a4_epson_config.dat' }
    @{ Name = 'Token'; Dat = 'token_epson_config.dat' }
)

# Find an already-installed WF-C579R queue to borrow its driver + port from.
$Source = Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.DriverName -like $ModelMatch -or $_.Name -like $ModelMatch } |
    Select-Object -First 1

if (-not $Source) {
    # No Epson on this machine - nothing to do. Silent so non-pharmacy or
    # non-Epson endpoints don't log noise.
    return
}

Write-Host "[INFO] Epson WF-C579R found ($($Source.DriverName)) - ensuring A4/Token queues..." -ForegroundColor Cyan
Write-Log "Add-Epson-TrayQueues: source queue '$($Source.Name)' driver '$($Source.DriverName)' port '$($Source.PortName)'"

foreach ($q in $Queues) {
    $name = $q.Name
    try {
        if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
            Add-Printer -Name $name -DriverName $Source.DriverName -PortName $Source.PortName -ErrorAction Stop
            Write-Host "[SUCCESS] Created queue '$name'" -ForegroundColor Green
            Write-Log "Add-Epson-TrayQueues: created queue '$name' on port '$($Source.PortName)'"
        } else {
            Write-Host "[INFO] Queue '$name' already present" -ForegroundColor DarkGray
            Write-Log "Add-Epson-TrayQueues: queue '$name' already present"
        }
    } catch {
        Write-Host "[ERROR] Failed to create queue '$name': $_" -ForegroundColor Red
        Write-Log "ERROR: Add-Epson-TrayQueues failed to create '$name' - $_"
        continue
    }

    # Replay the captured tray / paper-size / colour defaults, if we have a
    # blob for this queue. /Sr with 'd g' restores both the public default
    # DEVMODE and the Epson driver-private data (cassette + user-defined
    # "Token" size + grayscale). Capture must come from a matching driver
    # version - see printer-configs\README.md.
    $dat = Join-Path $ConfigDir $q.Dat
    if (Test-Path -LiteralPath $dat) {
        try {
            $p = Start-Process -FilePath 'rundll32.exe' `
                -ArgumentList @('printui.dll,PrintUIEntry', '/Sr', '/n', $name, '/a', $dat, 'd', 'g') `
                -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) {
                Write-Host "[SUCCESS] Applied saved tray settings to '$name'" -ForegroundColor Green
                Write-Log "Add-Epson-TrayQueues: restored DEVMODE for '$name' from '$($q.Dat)'"
            } else {
                Write-Host "[WARN] printui returned exit $($p.ExitCode) restoring '$name' - set tray by hand" -ForegroundColor Yellow
                Write-Log "WARN: Add-Epson-TrayQueues printui exit $($p.ExitCode) restoring '$name'"
            }
        } catch {
            Write-Host "[ERROR] Failed to restore settings for '$name': $_" -ForegroundColor Red
            Write-Log "ERROR: Add-Epson-TrayQueues restore failed for '$name' - $_"
        }
    } else {
        Write-Host "[WARN] No saved settings blob '$($q.Dat)' - set '$name' tray by hand once" -ForegroundColor Yellow
        Write-Log "WARN: Add-Epson-TrayQueues no DEVMODE blob at '$dat' for '$name'"
    }
}

# Remove the default "EPSON WF-C579R Series" queue (or any other WF-C579R queue
# that isn't A4/Token) so users and Titan only ever see the two logical queues.
# Guarded: only delete once BOTH A4 and Token are confirmed present, so a failed
# queue creation can never leave the machine with no way to print.
$wanted = $Queues.Name
$haveBoth = $wanted | ForEach-Object { Get-Printer -Name $_ -ErrorAction SilentlyContinue } |
    Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($haveBoth -eq $wanted.Count) {
    Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.DriverName -like $ModelMatch -and $_.Name -notin $wanted } |
        ForEach-Object {
            try {
                Remove-Printer -Name $_.Name -ErrorAction Stop
                Write-Host "[INFO] Removed surplus queue '$($_.Name)'" -ForegroundColor DarkGray
                Write-Log "Add-Epson-TrayQueues: removed surplus queue '$($_.Name)'"
            } catch {
                Write-Host "[WARN] Could not remove surplus queue '$($_.Name)': $_" -ForegroundColor Yellow
                Write-Log "WARN: Add-Epson-TrayQueues could not remove '$($_.Name)' - $_"
            }
        }
} else {
    Write-Host "[WARN] A4/Token not both present - leaving default queue in place" -ForegroundColor Yellow
    Write-Log "WARN: Add-Epson-TrayQueues skipped cleanup; only $haveBoth/$($wanted.Count) target queues exist"
}
