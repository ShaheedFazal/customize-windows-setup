<#
.SYNOPSIS
    Read-only diagnostic for Zebra (ZDesigner) print-driver plug-ins blocked by the
    HSS print-driver hardening baseline. Designed to be pushed site-wide via the
    SuperOps console.

.DESCRIPTION
    Confirms (without changing any state) whether the print spooler is blocking
    non-package-aware third-party driver plug-ins. Symptom on affected boxes:

        Event ID 808  "The print spooler failed to load a plug-in module
                       ...ZDesignerui.dll, error code 0x679"
                       ...ZDesignerLM.dll, error code 0x679

        0x679 = 1657 = ERROR_PRINTER_DRIVER_BLOCKED

    Likely cause is the Sept-2022 print-driver hardening applied by this toolkit's
    HSS baseline (CopyFilesPolicy / RedirectionGuardPolicy restrict the spooler to
    Microsoft-signed, package-aware plug-ins). Zebra's legacy ZDesigner driver is
    not package-aware, so its UI plug-in (ZDesignerui.dll) and language monitor
    (ZDesignerLM.dll) get blocked and the printers go dead / look uninstalled.

    This script ONLY READS. It makes no registry, driver, printer, or service
    changes. Everything is written to the console (captured by the SuperOps job
    log) and a transcript file is left on the endpoint as a backup.

.NOTES
    Pushed via SuperOps (runs as SYSTEM). Self-contained: no dependency on the
    customize-windows-setup repo being present. No automated tests (see AGENTS.md).
#>

$ErrorActionPreference = 'Continue'

# --- Self-contained logging ---------------------------------------------------
# SuperOps captures stdout, so everything goes to the console via Write-Log.
# A transcript file is also written for central collection / later retrieval.
$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$transcript = Join-Path $logDir "PrinterDriverBlock-Diag-$env:COMPUTERNAME.log"

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    try { Add-Content -LiteralPath $transcript -Value $Message -Encoding UTF8 } catch { }
}
function Write-Section {
    param([string]$Title)
    Write-Log ''
    Write-Log ('=' * 78)
    Write-Log "== $Title"
    Write-Log ('=' * 78)
}

# Fresh transcript per run so collected output is unambiguous.
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch { }

$os         = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$osCaption  = if ($os) { $os.Caption }     else { '<unknown>' }
$osBuild    = if ($os) { $os.BuildNumber } else { '<unknown>' }
$runUtc     = (Get-Date).ToUniversalTime().ToString('o')
$runLocal   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Write-Log "Printer driver-block diagnostic"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (UTC)   : $runUtc"
Write-Log "Run (local) : $runLocal"
Write-Log "OS          : $osCaption (build $osBuild)"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. Decode the error code so the SuperOps reader doesn't have to.
# -----------------------------------------------------------------------------
Write-Section '1. Error code 0x679 decoded'
try {
    $ex = [System.ComponentModel.Win32Exception]0x679
    Write-Log ("0x679 = {0} = {1}" -f 1657, $ex.Message)
    Write-Log "Interpretation: the spooler is ACTIVELY BLOCKING these plug-in modules"
    Write-Log "(policy block - ERROR_PRINTER_DRIVER_BLOCKED), not a missing/corrupt file."
} catch {
    Write-Log "ERROR decoding 0x679: $_"
}

# -----------------------------------------------------------------------------
# 2. Current print-driver hardening policy values (read-only).
# -----------------------------------------------------------------------------
Write-Section '2. Print-driver hardening policy values'

function Show-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        Write-Log ("  {0,-48} = {1}" -f $Name, $item.$Name)
    } catch {
        Write-Log ("  {0,-48} = <not set>" -f $Name)
    }
}

$printersKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers'
$pointPrintKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
$rpcKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'
$printCtrlKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print'

Write-Log "[$printersKey]"
Show-RegValue -Path $printersKey -Name 'CopyFilesPolicy'
Show-RegValue -Path $printersKey -Name 'RedirectionGuardPolicy'
Show-RegValue -Path $printersKey -Name 'DisableWebPnPDownload'

Write-Log "[$pointPrintKey]"
Show-RegValue -Path $pointPrintKey -Name 'RestrictDriverInstallationToAdministrators'
Show-RegValue -Path $pointPrintKey -Name 'NoWarningNoElevationOnInstall'

Write-Log "[$rpcKey] (full subkey dump)"
try {
    if (Test-Path -LiteralPath $rpcKey) {
        $rpc = Get-ItemProperty -LiteralPath $rpcKey -ErrorAction Stop
        $rpc.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { Write-Log ("  {0,-48} = {1}" -f $_.Name, $_.Value) }
    } else {
        Write-Log "  <subkey does not exist>"
    }
} catch {
    Write-Log "  ERROR reading RPC subkey: $_"
}

Write-Log "[$printCtrlKey]"
Show-RegValue -Path $printCtrlKey -Name 'RpcAuthnLevelPrivacyEnabled'

Write-Log ''
Write-Log "Block signature: CopyFilesPolicy=1 AND/OR RedirectionGuardPolicy=1 restricts"
Write-Log "the spooler to package-aware, Microsoft-signed plug-ins. Legacy ZDesigner is"
Write-Log "not package-aware -> ZDesignerui.dll / ZDesignerLM.dll blocked -> 808 / 0x679."

# -----------------------------------------------------------------------------
# 3. Installed printers.
# -----------------------------------------------------------------------------
Write-Section '3. Get-Printer'
try {
    $printers = Get-Printer -ErrorAction Stop |
        Select-Object Name, DriverName, PortName, PrinterStatus
    if ($printers) {
        $printers | Format-Table -AutoSize | Out-String -Width 4096 |
            ForEach-Object { $_.TrimEnd() } | Where-Object { $_ } |
            ForEach-Object { Write-Log $_ }
    } else {
        Write-Log "No printers returned."
    }
} catch {
    Write-Log "ERROR running Get-Printer: $_"
}

# -----------------------------------------------------------------------------
# 4. Zebra print drivers.
# -----------------------------------------------------------------------------
Write-Section '4. Get-PrinterDriver (Zebra / ZDesigner only)'
try {
    $zebra = Get-PrinterDriver -ErrorAction Stop | Where-Object {
        $_.Name -match 'Zebra|ZDesigner' -or $_.Manufacturer -match 'Zebra'
    } | Select-Object Name, Manufacturer, InfPath
    if ($zebra) {
        $zebra | Format-List | Out-String -Width 4096 |
            ForEach-Object { $_.TrimEnd("`r","`n") } |
            ForEach-Object { Write-Log $_ }
    } else {
        Write-Log "No Zebra/ZDesigner drivers currently registered (may have been unloaded)."
    }
} catch {
    Write-Log "ERROR running Get-PrinterDriver: $_"
}

# -----------------------------------------------------------------------------
# 5. Full UserData of the last ~10 Event ID 808s (the smoking gun).
# -----------------------------------------------------------------------------
Write-Section '5. PrintService/Admin - last 10 Event ID 808 (plug-in load failures)'
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-PrintService/Admin'; Id = 808
    } -MaxEvents 10 -ErrorAction Stop
    if ($events) {
        foreach ($evt in $events) {
            Write-Log ''
            Write-Log ("--- {0}  (RecordId {1}) ---" -f $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $evt.RecordId)
            Write-Log $evt.Message
            try {
                $userData = ([xml]$evt.ToXml()).Event.UserData.InnerXml
                if ($userData) { Write-Log ("UserData: {0}" -f $userData) }
            } catch {
                Write-Log "  (could not parse UserData XML: $_)"
            }
        }
    } else {
        Write-Log "No Event ID 808 entries found in PrintService/Admin."
    }
} catch {
    Write-Log "ERROR / no 808 events (log may be empty or disabled): $_"
}

# -----------------------------------------------------------------------------
# 6. Rule out a Windows cumulative update flipping the same block independently.
#    Incident window: 2026-06-08 ~07:43 local.
# -----------------------------------------------------------------------------
Write-Section '6. System log + hotfixes around the incident window'

Write-Log "-- Installed hotfixes (most recent 15) --"
try {
    Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending |
        Select-Object -First 15 HotFixID, Description, InstalledOn |
        Format-Table -AutoSize | Out-String -Width 4096 |
        ForEach-Object { $_.TrimEnd() } | Where-Object { $_ } |
        ForEach-Object { Write-Log $_ }
} catch {
    Write-Log "ERROR running Get-HotFix: $_"
}

Write-Log ''
Write-Log "-- System log: servicing / reboot / print events in last 48h --"
try {
    $since = (Get-Date).AddHours(-48)
    $sys = Get-WinEvent -FilterHashtable @{
        LogName = 'System'; StartTime = $since
    } -ErrorAction Stop | Where-Object {
        $_.ProviderName -match 'WindowsUpdateClient|Servicing|Spooler|Kernel-General|Print' -or
        $_.Id -in 19, 20, 43, 44, 1074, 6005, 6006, 7000, 7026, 7045
    } | Select-Object -First 40 TimeCreated, Id, ProviderName, LevelDisplayName, Message
    if ($sys) {
        foreach ($s in $sys) {
            $msg = ($s.Message -split "`r?`n")[0]
            Write-Log ("{0}  Id={1,-5} {2}  [{3}]  {4}" -f `
                $s.TimeCreated.ToString('MM-dd HH:mm:ss'), $s.Id, $s.ProviderName, $s.LevelDisplayName, $msg)
        }
    } else {
        Write-Log "No matching System log events in the last 48h."
    }
} catch {
    Write-Log "ERROR reading System log: $_"
}

# -----------------------------------------------------------------------------
# 7. Spooler service state (context only).
# -----------------------------------------------------------------------------
Write-Section '7. Print Spooler service state'
try {
    $svc = Get-Service -Name Spooler -ErrorAction Stop
    Write-Log ("Spooler: Status={0}, StartType={1}" -f $svc.Status, $svc.StartType)
} catch {
    Write-Log "ERROR reading Spooler service: $_"
}

Write-Section 'Diagnostic complete (read-only - no changes made)'
Write-Log "Transcript saved to: $transcript"
