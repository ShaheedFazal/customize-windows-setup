<#
.SYNOPSIS
    Read-only diagnostic for third-party print-driver plug-ins (Zebra ZDesigner,
    Brother, etc.) blocked from loading into the print spooler by image-load
    mitigations. Designed to be pushed site-wide via the SuperOps console.

.DESCRIPTION
    Symptom on affected boxes - Microsoft-Windows-PrintService/Admin Event ID 808:

        "The print spooler failed to load a plug-in module
         ...ZDesignerui.dll, error code 0x679"   (Zebra UI plug-in)
         ...ZDesignerLM.dll, error code 0x679     (Zebra language monitor)
         ...BRUIM15A.DLL,    error code 0x677     (Brother UI module)

    The error codes are decoded LIVE on the endpoint (section 1) rather than
    assumed. On a 2026 Win11 box, 0x679 (1657) decodes to:

        "The specified image file was blocked from loading because it does not
         enable a feature required by the process: Control Flow Guard"

    i.e. this is a *Control Flow Guard (CFG) image-load mitigation* block, NOT the
    CopyFilesPolicy / RedirectionGuardPolicy package-aware restriction. The spooler
    (or PrintIsolationHost) runs with CFG enforced; legacy vendor plug-ins that
    aren't built with CFG are refused by the loader, the queue stops working and
    can end up removed - which is why a previously-installed printer "disappears".

    This decides the fix: the lever is the *exploit-protection / process-mitigation*
    config (which the HSS baseline applies, and which a Windows cumulative update
    can also tighten), not the four printer GroupPolicy values. Those policy values
    are still captured (section 2) for completeness.

    This script ONLY READS. It makes no registry, driver, printer, service or
    mitigation changes. Everything is written to the console (captured by the
    SuperOps job log) and a transcript file is left on the endpoint as a backup.

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
function Write-Block {
    # Render any object as a clean multi-line block into the log.
    param($InputObject, [string]$Format = 'Table')
    if ($null -eq $InputObject) { return }
    if ($Format -eq 'List') {
        $text = $InputObject | Format-List | Out-String -Width 4096
    } else {
        $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096
    }
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.TrimEnd()) { Write-Log $line.TrimEnd() }
    }
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
# 1. Decode the error codes LIVE on the endpoint (don't assume their meaning).
# -----------------------------------------------------------------------------
Write-Section '1. Spooler plug-in error codes decoded (live)'
foreach ($code in 0x679, 0x677, 0x5) {
    try {
        $ex = [System.ComponentModel.Win32Exception]$code
        Write-Log ("0x{0:X} = {1} = {2}" -f $code, [int]$code, $ex.Message)
    } catch {
        Write-Log ("0x{0:X}: ERROR decoding - {1}" -f $code, $_)
    }
}
Write-Log ''
Write-Log "If the message mentions 'Control Flow Guard', the spooler is refusing a"
Write-Log "plug-in DLL that isn't CFG-enabled -> this is an exploit-protection /"
Write-Log "process-mitigation block (see section 6), not a missing/corrupt file."

# -----------------------------------------------------------------------------
# 2. Print-driver hardening policy values (captured for completeness).
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

# -----------------------------------------------------------------------------
# 3. ALL installed printers (does the missing queue still exist?).
# -----------------------------------------------------------------------------
Write-Section '3. Get-Printer (all queues)'
try {
    $printers = Get-Printer -ErrorAction Stop |
        Select-Object Name, DriverName, PortName, Shared, PrinterStatus
    if ($printers) {
        Write-Block $printers 'Table'
    } else {
        Write-Log "No printers returned."
    }
} catch {
    Write-Log "ERROR running Get-Printer: $_"
}

# -----------------------------------------------------------------------------
# 4. ALL printer drivers (so a missing-printer's driver shows even if the queue
#    is gone). Zebra/Brother are flagged.
# -----------------------------------------------------------------------------
Write-Section '4. Get-PrinterDriver (all - Zebra/Brother flagged)'
try {
    $drivers = Get-PrinterDriver -ErrorAction Stop | ForEach-Object {
        $flag = ''
        if ($_.Name -match 'Zebra|ZDesigner' -or $_.Manufacturer -match 'Zebra')   { $flag = '<< ZEBRA'   }
        if ($_.Name -match 'Brother'         -or $_.Manufacturer -match 'Brother') { $flag = '<< BROTHER' }
        [pscustomobject]@{
            Flag         = $flag
            Name         = $_.Name
            Manufacturer = $_.Manufacturer
            InfPath      = $_.InfPath
        }
    }
    if ($drivers) {
        Write-Block ($drivers | Select-Object Flag, Name, Manufacturer) 'Table'
        Write-Log ''
        Write-Log "-- INF paths --"
        foreach ($d in $drivers) { Write-Log ("  {0,-40} {1}" -f $d.Name, $d.InfPath) }
    } else {
        Write-Log "No printer drivers registered."
    }
} catch {
    Write-Log "ERROR running Get-PrinterDriver: $_"
}

# -----------------------------------------------------------------------------
# 5. Full UserData of the last ~30 Event ID 808s (the smoking gun, all vendors).
# -----------------------------------------------------------------------------
Write-Section '5. PrintService/Admin - last 30 Event ID 808 (plug-in load failures)'
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-PrintService/Admin'; Id = 808
    } -MaxEvents 30 -ErrorAction Stop
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
# 6. Process mitigations on the print binaries (CFG = the actual lever).
# -----------------------------------------------------------------------------
Write-Section '6. Exploit-protection / process mitigations on print binaries'
if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
    Write-Log "Get-ProcessMitigation not available on this host."
} else {
    function Show-Mitigation {
        param([string]$Label, [scriptblock]$Getter)
        Write-Log ''
        Write-Log "-- $Label --"
        try {
            $m = & $Getter
            if ($null -eq $m) { Write-Log "  <no mitigation data>"; return }
            foreach ($prop in 'CFG','BinarySignature','ImageLoad','Payload') {
                $sub = $m.$prop
                if ($null -ne $sub) {
                    Write-Log "  [$prop]"
                    Write-Block $sub 'List'
                }
            }
        } catch {
            Write-Log "  ERROR: $_"
        }
    }
    Show-Mitigation 'System default'                 { Get-ProcessMitigation -System }
    Show-Mitigation 'spoolsv.exe'                    { Get-ProcessMitigation -Name 'spoolsv.exe' }
    Show-Mitigation 'PrintIsolationHost.exe'         { Get-ProcessMitigation -Name 'PrintIsolationHost.exe' }
    Show-Mitigation 'printfilterpipelinesvc.exe'     { Get-ProcessMitigation -Name 'printfilterpipelinesvc.exe' }
}

# -----------------------------------------------------------------------------
# 7. The blocked plug-in DLL files - exist? version? signature? CFG?
# -----------------------------------------------------------------------------
Write-Section '7. Blocked plug-in DLLs on disk (existence / signature / version)'
$driverRoot = "$env:WINDIR\System32\spool\DRIVERS\x64\3"
$dllNames   = @('ZDesignerui.dll','ZDesignerLM.dll','BRUIM15A.DLL')
foreach ($name in $dllNames) {
    Write-Log ''
    Write-Log "-- $name --"
    $hits = @()
    $direct = Join-Path $driverRoot $name
    if (Test-Path -LiteralPath $direct) { $hits += $direct }
    try {
        $hits += (Get-ChildItem -LiteralPath $driverRoot -Filter $name -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    } catch { }
    $hits = $hits | Select-Object -Unique
    if (-not $hits) {
        Write-Log "  not found under $driverRoot"
        continue
    }
    foreach ($path in $hits) {
        try {
            $fi  = Get-Item -LiteralPath $path -ErrorAction Stop
            $ver = (Get-Item -LiteralPath $path).VersionInfo.FileVersion
            Write-Log ("  Path     : {0}" -f $path)
            Write-Log ("  Version  : {0}   Size: {1} bytes   Modified: {2}" -f $ver, $fi.Length, $fi.LastWriteTime)
            $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
            $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '<none>' }
            Write-Log ("  Signature: {0}  Signer: {1}" -f $sig.Status, $signer)
        } catch {
            Write-Log "  ERROR inspecting $path : $_"
        }
    }
}

# -----------------------------------------------------------------------------
# 8. Printer/driver add+remove history (when did the queue disappear?).
# -----------------------------------------------------------------------------
Write-Section '8. Printer add/remove history (PrintService/Operational)'
try {
    $opEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-PrintService/Operational'
        Id      = 300, 301, 302, 600, 601, 602
    } -MaxEvents 40 -ErrorAction Stop
    if ($opEvents) {
        foreach ($e in $opEvents) {
            $msg = ($e.Message -split "`r?`n")[0]
            Write-Log ("{0}  Id={1,-4} {2}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $e.Id, $msg)
        }
    } else {
        Write-Log "No printer add/remove events found (log may be disabled)."
    }
} catch {
    Write-Log "No PrintService/Operational events (log may be disabled): $_"
}

# -----------------------------------------------------------------------------
# 9. Rule out a Windows cumulative update tightening the block independently.
#    Incident window: 2026-06-08 ~07:43 local.
# -----------------------------------------------------------------------------
Write-Section '9. Hotfixes + servicing/reboot history'
Write-Log "-- Installed hotfixes (most recent 15) --"
try {
    Write-Block (Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending |
        Select-Object -First 15 HotFixID, Description, InstalledOn) 'Table'
} catch {
    Write-Log "ERROR running Get-HotFix: $_"
}

Write-Log ''
Write-Log "-- System log: servicing / reboot / print events in last 72h --"
try {
    $since = (Get-Date).AddHours(-72)
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
        Write-Log "No matching System log events in the last 72h."
    }
} catch {
    Write-Log "ERROR reading System log: $_"
}

# -----------------------------------------------------------------------------
# 10. Spooler service state (context only).
# -----------------------------------------------------------------------------
Write-Section '10. Print Spooler service state'
try {
    $svc = Get-Service -Name Spooler -ErrorAction Stop
    Write-Log ("Spooler: Status={0}, StartType={1}" -f $svc.Status, $svc.StartType)
} catch {
    Write-Log "ERROR reading Spooler service: $_"
}

Write-Section 'Diagnostic complete (read-only - no changes made)'
Write-Log "Transcript saved to: $transcript"
